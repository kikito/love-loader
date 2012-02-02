-- private stuff

local loader = require 'love-loader'


local spiral
local spiralAngle = 0
local screenWidth, screenHeight = love.graphics.getWidth(), love.graphics.getHeight()

local function drawSpiral()
  local w,h = spiral:getWidth(), spiral:getHeight()
  local x,y = screenWidth/2, screenHeight/2
  love.graphics.draw(spiral, x, y, spiralAngle, 1, 1, w/2, h/2)
end

local function drawLoadingBar()
  local separation = 30;
  local w = screenWidth - 2*separation
  local h = 50;
  local x,y = separation, screenHeight - separation - h;
  love.graphics.rectangle("line", x, y, w, h)

  x, y = x + 3, y + 3
  w, h = w - 6, h - 7

  if loader.loadedCount > 0 then
    w = w * (loader.loadedCount / loader.resourceCount)
  end
  love.graphics.rectangle("fill", x, y, w, h)
end

-- the state

local loadingState = {}

function loadingState.start(media, finishCallback)

  math.randomseed(os.time())

  spiral = love.graphics.newImage('media/spiral.png')

  for i=1,50 do
    loader.newImage(media.images, i, 'media/knoll.png')
  end

  loader.newSource(   media.sounds, 'astro_fusion', 'media/astro-fusion.ogg', 'stream')
  loader.newSource(   media.sounds, 'space',        'media/space.ogg', 'stream')
  loader.newSoundData(media.sounds, 'space2',       'media/space.ogg')

  print("started loading")

  loader.start(finishCallback, print)
end

function loadingState.draw()
  drawSpiral()
  drawLoadingBar()
end

function loadingState.update(dt)
  loader.update()
  spiralAngle = spiralAngle + 2*dt
end

return loadingState
