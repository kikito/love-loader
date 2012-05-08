-- love-loaver v1.1.2 (2012-04)
-- Copyright (c) 2011 Enrique García Cota
-- Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
-- The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require "love.filesystem"
require "love.image"
require "love.audio"
require "love.sound"

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

-- compatibility with LÖVE v0.7.x and 0.8.x
local function setInThread(thread, key, value)
  local set = thread.set or thread.send
  return set(thread, key, value)
end

local function getFromThread(thread, key)
  local get = thread.get or thread.receive
  return get(thread, key)
end

local producer = love.thread.getThread('loader')

if producer then

  local requestParam, resource
  local done = false

  while not done do

    for _,kind in pairs(resourceKinds) do
      requestParam = getFromThread(producer, kind.requestKey)
      if requestParam then
        resource = kind.constructor(requestParam)
        setInThread(producer, kind.resourceKey, resource)
      end
    end

    done = getFromThread(producer, "done")
  end

else

  local loader = {}

  local pending = {}
  local callbacks = {}
  local resourceBeingLoaded

  local pathToThisFile = (...):gsub("%.", "/") .. ".lua"

  local function shift(t)
    return table.remove(t,1)
  end

  local function newResource(kind, holder, key, requestParam)
    pending[#pending + 1] = {
      kind = kind, holder = holder, key = key, requestParam = requestParam
    }
  end

  local function getResourceFromThreadIfAvailable(thread)
    local errorMessage = getFromThread(thread,"error")
    assert(not errorMessage, errorMessage)

    local data, resource
    for name,kind in pairs(resourceKinds) do
      data = getFromThread(thread, kind.resourceKey)
      if data then
        resource = kind.postProcess and kind.postProcess(data, resourceBeingLoaded) or data
        resourceBeingLoaded.holder[resourceBeingLoaded.key] = resource
        loader.loadedCount = loader.loadedCount + 1
        callbacks.oneLoaded(resourceBeingLoaded.kind, resourceBeingLoaded.holder, resourceBeingLoaded.key)
        resourceBeingLoaded = nil
      end
    end
  end

  local function requestNewResourceToThread(thread)
    resourceBeingLoaded = shift(pending)
    local requestKey = resourceKinds[resourceBeingLoaded.kind].requestKey
    setInThread(thread, requestKey, resourceBeingLoaded.requestParam)
  end

  local function endThreadIfAllLoaded(thread)
    if not resourceBeingLoaded and #pending == 0 then
      setInThread(thread,"done",true)
      callbacks.allLoaded()
    end
  end


  -- public interface starts here

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

    callbacks.allLoaded = allLoadedCallback or function() end
    callbacks.oneLoaded = oneLoadedCallback or function() end

    local thread = love.thread.newThread("loader", pathToThisFile)

    loader.loadedCount = 0
    loader.resourceCount = #pending
    thread:start()
  end

  function loader.update()
    local thread = love.thread.getThread("loader")
    if thread then
      if resourceBeingLoaded then
        getResourceFromThreadIfAvailable(thread)
        endThreadIfAllLoaded(thread)
      elseif #pending > 0 then
        requestNewResourceToThread(thread)
      end
    end
  end

  return loader
end
