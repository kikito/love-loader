
local loadingState = require 'loadingState'
local playingState = require 'playingState'
local currentState = nil

local media = { images = {}, sounds = {} }

local function loadingFinished()
  print("loading finished")
  currentState = playingState
  currentState.start(media)
end

function love.load()
  currentState = loadingState
  currentState.start(media, loadingFinished)
end

function love.draw()
  currentState.draw()
end

function love.update(dt)
  currentState.update(dt)
end

function love.keypressed(key)
  if key == 'escape' then
    local f = love.event.quit or love.event.push
    f('q')
  end
  if currentState.keypressed then
    currentState.keypressed(key)
  end
end
