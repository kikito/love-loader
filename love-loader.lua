require "love.filesystem"
require "love.image"
require "love.audio"
require "love.sound"

local loader = {
  _VERSION     = 'love-loader v2.0.1',
  _DESCRIPTION = 'Object Orientation for Lua',
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
    constructor = love.image.newImageData,
    postProcess = function(data)
      return love.graphics.newImage(data)
    end
  },
  source = {
    requestKey  = "sourcePath",
    resourceKey = "source",
    constructor = function(path)
      return love.audio.newSource(path)
    end
  },
  stream = {
    requestKey  = "streamPath",
    resourceKey = "stream",
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
  }
}

local CHANNEL_PREFIX = "loader_"

local loaded = ...
if loaded == true then
  local requestParam, resource
  local done = false

  local doneChannel = love.thread.getChannel(CHANNEL_PREFIX .. "is_done")

  while not done do

    for _,kind in pairs(resourceKinds) do
      local loader = love.thread.getChannel(CHANNEL_PREFIX .. kind.requestKey)
      requestParam = loader:pop()
      if requestParam then
        resource = kind.constructor(requestParam)
        local producer = love.thread.getChannel(CHANNEL_PREFIX .. kind.resourceKey)
        producer:push(resource)
      end
    end

    done = doneChannel:pop()
  end

else
  local alreadyCalled = false
  local pending = {}
  local callbacks = {}
  local resourceBeingLoaded

  local separator = _G.package.config:sub(1,1)
  local pathToThisFile = (...):gsub("%.", separator) .. ".lua"

  local function shift(t)
    return table.remove(t,1)
  end

  local function newResource(kind, holder, key, requestParam)
    pending[#pending + 1] = {
      kind = kind, holder = holder, key = key, requestParam = requestParam
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
    channel:push(resourceBeingLoaded.requestParam)
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

  function loader.newSource(holder, key, path, sourceType)
    local kind = (sourceType == 'stream' and 'stream' or 'source')
    newResource(kind, holder, key, path)
  end

  function loader.newSoundData(holder, key, pathOrDecoder)
    newResource('soundData', holder, key, pathOrDecoder)
  end

  function loader.newImageData(holder, key, path)
    newResource('imageData', holder, key, path)
  end

  function loader.start(allLoadedCallback, oneLoadedCallback)
    alreadyCalled = false
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
        elseif not alreadyCalled then
          alreadyCalled = true
          endThreadIfAllLoaded()
        end
      else
        local errorMessage = loader.thread:getError()
        assert(not errorMessage, errorMessage)
      end
    end
  end

  return loader
end
