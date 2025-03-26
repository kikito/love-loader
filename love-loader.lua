
require "love.filesystem"
require "love.image"
require "love.audio"
require "love.sound"

---@class LoveLoader
-- Static fields --
---@field _VERSION string
---@field _DESCRIPTION string
---@field _URL string
---@field _LICENSE string
-- Functions --
---@field newImage function
---@field newFont function
---@field newBMFont function
---@field newSource function
---@field newSoundData function
---@field newImageData function
---@field newCompressedData function
---@field rawData function
---@field newVideo function
---@field read function
---@field start function
---@field update function
-- Dynamic fields --
---@field loadedCount? number
---@field resourceCount? number
---@field thread? love.Thread

-- Due to the if statement LuaLS will think that the fields are missing.
---@type LoveLoader
---@diagnostic disable-next-line: missing-fields
local loader = {
  _VERSION     = 'love-loader v2.0.3',
  _DESCRIPTION = 'Threaded resource loading for LÖVE',
  _URL         = 'https://github.com/kikito/love-loader',
  _LICENSE     = [[
    MIT LICENSE

    Copyright (c) 2014 Enrique García Cota, Tanner Rogalsky

    Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the
    "Software"), to deal in the Software without restriction, including
    without limitation the rights to use, copy, modify, merge, publish,
    distribute, sublicense, and/or sell copies of the Software, and to
    permit persons to whom the Software is furnished to do so, subject to
    the following conditions:

    The above copyright notice and this permission notice shall be included
    in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
    OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
    IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
    CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
    TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
    SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
  ]]
}


---@alias ResourceKind string
---| "newImage"                 # Load an Image
---| "newFont"                  # Load a Font
---| "newBMFont"                # Load a Bitmap Font
---| "newSource"                # Load a Source
---| "newSoundData"             # Load a SoundData
---| "newImageData"             # Load an ImageData
---| "newCompressedData"        # Load a CompressedData
---| "rawData"                  # Load raw text data
---| "newVideo"                 # Load a Video

---@class ResourceKindConstructor
---@field requestKey string
---@field resourceKey string
---@field constructor fun(path: string): any, ...
---@field postProcess? fun(data: any, resource: any): any

---@type table<ResourceKind, ResourceKindConstructor>
local resourceKinds = {
  image = {
    requestKey  = "imagePath",
    resourceKey = "imageData",
    constructor = function (path)
      if love.image.isCompressed(path) then
        return love.image.newCompressedData(path)
      else
        return love.image.newImageData(path)
      end
    end,
    postProcess = function(data)
      return love.graphics.newImage(data)
    end
  },
  staticSource = {
    requestKey  = "staticPath",
    resourceKey = "staticSource",
    constructor = function(path)
      return love.audio.newSource(path, "static")
    end
  },
  font = {
    requestKey  = "fontPath",
    resourceKey = "fontData",
    constructor = function(path)
      -- we don't use love.filesystem.newFileData directly here because there
      -- are actually two arguments passed to this constructor which in turn
      -- invokes the wrong love.filesystem.newFileData overload
      return love.filesystem.newFileData(path)
    end,
    postProcess = function(data, resource)
      local path, size = unpack(resource.requestParams)
      return love.graphics.newFont(data, size)
    end
  },
  BMFont = {
    requestKey  = "fontBMPath",
    resourceKey = "fontBMData",
    constructor = function(path)
      return love.filesystem.newFileData(path)
    end,
    postProcess = function(data, resource)
      local imagePath, glyphsPath  = unpack(resource.requestParams)
      local glyphs = love.filesystem.newFileData(glyphsPath)
      ---@diagnostic disable-next-line: param-type-mismatch
      return love.graphics.newFont(glyphs,data)
    end
  },
  streamSource = {
    requestKey  = "streamPath",
    resourceKey = "streamSource",
    constructor = function(path)
      return love.audio.newSource(path, "stream")
    end
  },
  soundData = {
    requestKey  = "soundDataPathOrDecoder",
    resourceKey = "soundData",
    constructor = love.sound.newSoundData
  },
  imageData = {
    requestKey  = "imageDataPath",
    resourceKey = "rawImageData",
    constructor = love.image.newImageData
  },
  compressedData = {
    requestKey  = "compressedDataPath",
    resourceKey = "rawCompressedData",
    constructor = love.image.newCompressedData
  },
  rawData = {
    requestKey  = "rawDataPath",
    resourceKey = "rawData",
    constructor = love.filesystem.read
  },
  video = {
		requestKey  = "videoDataPath",
		resourceKey = "video",
		constructor = love.graphics.newVideo
	}
}

local CHANNEL_PREFIX = "loader_"

local loaded = ...
if loaded == true then
  local requestParams, resource
  local done = false

  local doneChannel = love.thread.getChannel(CHANNEL_PREFIX .. "is_done")

  while not done do

    for _,kind in pairs(resourceKinds) do
      local loaderChannel = love.thread.getChannel(CHANNEL_PREFIX .. kind.requestKey)
      requestParams = loaderChannel:pop()
      if requestParams then
        resource = kind.constructor(unpack(requestParams))
        local producer = love.thread.getChannel(CHANNEL_PREFIX .. kind.resourceKey)
        producer:push(resource)
      end
    end

    done = doneChannel:pop()
  end

else

  local pending = {}

  ---@class CallbackHolder
  ---@field allLoaded function
  ---@field oneLoaded function

  -- LuaLS gets happy when this is prepopulated with a table that has the allLoaded and oneLoaded functions. --
  -- It's honestly for the best.
  ---@type CallbackHolder
  local callbacks = {
    allLoaded = function() end,
    oneLoaded = function() end
  }
  local resourceBeingLoaded

  --- Expected to have the filename path of this file in order to read itself
  --- to dispatch a worker thread to load the resources.
  ---
  --- **Failing to find itself will result on a crash if** `loader.start` **gets called.**
  ---@type string
  local pathToThisFile = (...):gsub("%.", "/") .. ".lua"

  if love.filesystem.getInfo(pathToThisFile) == nil and type(debug) == "table" and type(debug.getinfo) == "function" then
    pathToThisFile = debug.getinfo(1).source:match("@?(.*)")
  end

  --- Removes the first item from the table.
  --- Returns the removed item.
  ---@param t table The table to remove the first item from.
  ---@return any
  local function shift(t)
    return table.remove(t, 1)
  end

  --- Macro used to add a resource to the pending list.
  ---@param kind ResourceKind What constructor to use to create the resource.
  ---@param holder table What table to store the resource in.
  ---@param key string What key to use to store the resource in the table.
  ---@param ...? any Additional parameters to pass to the constructor.
  ---@return nil
  local function newResource(kind, holder, key, ...)
    pending[#pending + 1] = {
      kind = kind, holder = holder, key = key, requestParams = {...}
    }
  end

  local function getResourceFromThreadIfAvailable()
    local data, resource
    for _, kind in pairs(resourceKinds) do
      local channel = love.thread.getChannel(CHANNEL_PREFIX .. kind.resourceKey)
      data = channel:pop()
      if data then
        resource = kind.postProcess and kind.postProcess(data, resourceBeingLoaded) or data
        resourceBeingLoaded.holder[resourceBeingLoaded.key] = resource
        loader.loadedCount = loader.loadedCount + 1
        callbacks.oneLoaded(resourceBeingLoaded.kind, resourceBeingLoaded.holder, resourceBeingLoaded.key)
        resourceBeingLoaded = nil
      end
    end
  end

  --- Sends resorce request to the aplicable request Thread channel.
  ---@return nil
  local function requestNewResourceToThread()
    resourceBeingLoaded = shift(pending)
    local requestKey = resourceKinds[resourceBeingLoaded.kind].requestKey
    local channel = love.thread.getChannel(CHANNEL_PREFIX .. requestKey)
    channel:push(resourceBeingLoaded.requestParams)
  end

  --- Tells to the worker thread that it can safely break from
  --- it's loop and terminate it's execution when there's no more resources to load.
  ---@return nil
  local function endThreadIfAllLoaded()
    if not resourceBeingLoaded and #pending == 0 then
      love.thread.getChannel(CHANNEL_PREFIX .. "is_done"):push(true)
      callbacks.allLoaded()
    end
  end

  -- ----------------------------------------------- --
  -- PUBLIC API                                      --
  -- ----------------------------------------------- --

  --- Loads a Image.
  ---@see love.graphics.newImage
  ---@param holder table The table where the image will be stored.
  ---@param key string The key to store the image under.
  ---@param path string The path to the image file.
  ---@return nil
  function loader.newImage(holder, key, path)
    newResource('image', holder, key, path)
  end

  --- Loads a Font.
  ---@see love.graphics.newFont
  ---@param holder table The table where the font will be stored.
  ---@param key string The key to store the font under.
  ---@param path string The path to the font file.
  ---@param size? number The size of the font.
  ---@return nil
  function loader.newFont(holder, key, path, size)
    newResource('font', holder, key, path, size)
  end

  --- Loads a Bitmap Font.
  ---@see love.graphics.newFont
  ---@param holder table The table where the font will be stored.
  ---@param key string The key to store the font under.
  ---@param path string The path to the font file.
  ---@param glyphsPath? string The path to the glyphs file.
  ---@return nil
  function loader.newBMFont(holder, key, path, glyphsPath)
    newResource('font', holder, key, path, glyphsPath)
  end

  --- Loads an audio source.
  ---@see love.audio.newSource
  ---@param holder table The table where the audio source will be stored.
  ---@param key string The key to store the audio source under.
  ---@param path string The path to the audio file.
  ---@param sourceType? love.SourceType The type of audio source to load.
  ---@return nil
  function loader.newSource(holder, key, path, sourceType)
    local kind = (sourceType == 'static' and 'staticSource' or 'streamSource')
    newResource(kind, holder, key, path)
  end

  --- Loads a sound as a raw SoundData object.
  ---@see love.sound.newSoundData
  ---@param holder table The table where the sound will be stored.
  ---@param key string The key to store the sound under.
  ---@param pathOrDecoder? any The path to the sound file or a decoder function.
  function loader.newSoundData(holder, key, pathOrDecoder)
    newResource('soundData', holder, key, pathOrDecoder)
  end

  --- Loads an image as an raw ImageData object.
  ---@see love.image.newImageData
  ---@param holder table The table where the imageData will be stored.
  ---@param key string The key to store the imageData under.
  ---@param path string The path to the image file.
  ---@return nil
  function loader.newImageData(holder, key, path)
    newResource('imageData', holder, key, path)
  end

  --- Loads a newCompressedData from an image.
  ---@see love.image.newCompressedData
  ---@param holder table The table where the compressedData will be stored.
  ---@param key string The key to store the compressedData under.
  ---@param path string The path to the image file.
  ---@return nil
  function loader.newCompressedData(holder, key, path)
    newResource('compressedData', holder, key, path)
  end

  --- Useful to read raw data, such as text.
  ---@see love.filesystem.read
  ---@param holder table The table where the rawData will be stored.
  ---@param key string The key to store the rawData under.
  ---@param path string The path to the file.
  ---@return nil
  function loader.read(holder, key, path)
    newResource('rawData', holder, key, path)
  end

  --- Starts the asset loading process on another thread.
  ---@param allLoadedCallback function Callback function that is called when all assets are loaded
  ---@param oneLoadedCallback function Callback function that is called when each asset is loaded
  ---@return nil
  function loader.start(allLoadedCallback, oneLoadedCallback)

    callbacks.allLoaded = allLoadedCallback or function() end
    callbacks.oneLoaded = oneLoadedCallback or function() end

    local thread = love.thread.newThread(pathToThisFile)

    loader.loadedCount = 0
    loader.resourceCount = #pending
    thread:start(true)
    loader.thread = thread
  end

  --- Checks the state of the worker thread.
  --- - It makes sure that the worker thread is running, raises an error if applicable.
  --- - Transfers asset pointers to the main thread.
  --- - It doesn't use delta time to function.
  ---@return nil
  function loader.update()
    if loader.thread then
      if loader.thread:isRunning() then
        if resourceBeingLoaded then
          getResourceFromThreadIfAvailable()
        elseif #pending > 0 then
          requestNewResourceToThread()
        else
          endThreadIfAllLoaded()
          loader.thread = nil
        end
      else
        local errorMessage = loader.thread:getError()
        assert(not errorMessage, errorMessage)
      end
    end
  end

  return loader
end
