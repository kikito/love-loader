-- love-loaver v0.5 (2012-01)
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
    inputName   = "imagePath",
    outputName  = "imageData",
    constructor = love.image.newImageData,
    postProcess = function(data)
      return love.graphics.newImage(data)
    end
  },
  source = {
    inputName   = "sourcePath",
    outputName  = "source",
    constructor = love.audio.newSource
  },
  stream = {
    inputName   = "streamPath",
    outputName  = "stream",
    constructor = function(path)
      return love.audio.newSource(path, "stream")
    end
  }
}

local producer = love.thread.getThread('loader')

if producer then

  local input, output
  local done = false

  while not done do

    for _,kind in pairs(resourceKinds) do
      input = producer:receive( kind.inputName )
      if input then
        output = kind.constructor( input )
        producer:send( kind.outputName, output )
      end
    end

    done = producer:receive( "done" )
  end

else

  local loader = {}

  local pending = {}
  local callbacks = {}
  local resourceBeingLoaded

  local pathToThisFile = ({...})[1] .. ".lua"

  local function shift(t)
    return table.remove(t,1)
  end

  local function newResource(kind, holder, key, input)
    pending[#pending + 1] = {
      kind = kind, holder = holder, key = key, input = input
    }
  end

  local function consumeFromThread(thread)
    local errorMessage = thread:receive("error")
    assert(not errorMessage, errorMessage)

    local data, resource
    for name,kind in pairs(resourceKinds) do
      data = thread:receive(kind.outputName)
      if data then
        resource = kind.postProcess and kind.postProcess(data, resourceBeingLoaded) or data
        resourceBeingLoaded.holder[resourceBeingLoaded.key] = resource
        loader.loadedCount = loader.loadedCount + 1
        callbacks.loaded(resourceBeingLoaded.kind, resourceBeingLoaded.holder, resourceBeingLoaded.key)
        resourceBeingLoaded = nil
      end
    end
  end

  local function requestToThread(thread)
    resourceBeingLoaded = shift(pending)
    local inputName = resourceKinds[resourceBeingLoaded.kind].inputName
    thread:send(inputName, resourceBeingLoaded.input)
  end

  local function killThreadIfDone(thread)
    if #pending == 0 then
      thread:send("done", true)
      callbacks.finished()
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

  function loader.start(finishedCallback, loadedCallback)

    callbacks.finished = finishedCallback or function() end
    callbacks.loaded   = loadedCallback or function() end

    local thread = love.thread.newThread("loader", pathToThisFile)

    loader.loadedCount = 0
    loader.resourceCount = #pending
    thread:start()
  end

  function loader.update()
    local thread = love.thread.getThread("loader")
    if thread then
      if resourceBeingLoaded then
        consumeFromThread(thread)
        killThreadIfDone(thread)
      elseif #pending > 0 then
        requestToThread(thread)
      end
    end
  end

  return loader
end
