require "love.filesystem"
require "love.image"
require "love.audio"
require "love.sound"

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
      local loader = love.thread.getChannel(CHANNEL_PREFIX .. kind.requestKey)
      requestParams = loader:pop()
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
  local callbacks = {}
  local resourceBeingLoaded

  local pathToThisFile = (...):gsub("%.", "/") .. ".lua"

  local function shift(t)
    return table.remove(t,1)
  end

  local function newResource(kind, holder, key, ...)
    pending[#pending + 1] = {
      kind = kind, holder = holder, key = key, requestParams = {...}
    }
  end

  local function getResourceFromThreadIfAvailable()
    local data, resource
    for name,kind in pairs(resourceKinds) do
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

  local function requestNewResourceToThread()
    resourceBeingLoaded = shift(pending)
    local requestKey = resourceKinds[resourceBeingLoaded.kind].requestKey
    local channel = love.thread.getChannel(CHANNEL_PREFIX .. requestKey)
    channel:push(resourceBeingLoaded.requestParams)
  end

  local function endThreadIfAllLoaded()
    if not resourceBeingLoaded and #pending == 0 then
      love.thread.getChannel(CHANNEL_PREFIX .. "is_done"):push(true)
      callbacks.allLoaded()
    end
  end

  -----------------------------------------------------

  function loader.newImage(holder, key, path)
    newResource('image', holder, key, path)
  end

  function loader.newFont(holder, key, path, size)
    newResource('font', holder, key, path, size)
  end

  function loader.newBMFont(holder, key, path, glyphsPath)
    newResource('font', holder, key, path, glyphsPath)
  end

  function loader.newSource(holder, key, path, sourceType)
    local kind = (sourceType == 'static' and 'staticSource' or 'streamSource')
    newResource(kind, holder, key, path)
  end

  function loader.newSoundData(holder, key, pathOrDecoder)
    newResource('soundData', holder, key, pathOrDecoder)
  end

  function loader.newImageData(holder, key, path)
    newResource('imageData', holder, key, path)
  end
  
  function loader.newCompressedData(holder, key, path)
    newResource('compressedData', holder, key, path)
  end

  function loader.start(allLoadedCallback, oneLoadedCallback)

    callbacks.allLoaded = allLoadedCallback or function() end
    callbacks.oneLoaded = oneLoadedCallback or function() end

    local thread = love.thread.newThread(pathToThisFile)

    loader.loadedCount = 0
    loader.resourceCount = #pending
    thread:start(true)
    loader.thread = thread
  end

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
