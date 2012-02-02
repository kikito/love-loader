-- private stuff

local random = math.random
local screenWidth, screenHeight = love.graphics.getWidth(), love.graphics.getHeight()

local knolls = {}


local function pacman(number, min, max)
  if number < min then return max end
  if number > max then return min end
  return number
end

local function resetKnollVelocity(knoll)
  knoll.vx = (random() - 0.5) * 30
  knoll.vy = (random() - 0.5) * 30
  knoll.entropy = 0
  return knoll
end

local function newKnoll(image)
  return resetKnollVelocity({ x = random(screenWidth), y = random(screenHeight), image = image })
end

local function updateKnoll(knoll, dt)
  knoll.x = pacman(knoll.x + knoll.vx * dt, -50, screenWidth + 50)
  knoll.y = pacman(knoll.y + knoll.vy * dt, -50, screenHeight + 50)
  knoll.entropy = knoll.entropy + dt
  if random() * knoll.entropy > 0.9  then
    resetKnollVelocity(knoll)
  end
end

local function drawKnoll(knoll)
  love.graphics.draw(knoll.image, knoll.x, knoll.y)
end

-- the state

local playingState = {}

local spaceSound, spaceSound2

function playingState.start(media)
  love.audio.play(media.sounds.astro_fusion)
  for i=1,50 do
    knolls[i] = newKnoll(media.images[i])
  end
  spaceSound = media.sounds.space
  spaceSound2 = love.audio.newSource(media.sounds.space2)
end

function playingState.draw()
  for i=1,50 do drawKnoll(knolls[i]) end
end

function playingState.update(dt)
  for i=1,50 do updateKnoll(knolls[i], dt) end
end

function playingState.keypressed(key)
  if key == ' '     then love.audio.play(spaceSound) end
  if key == 'return' then love.audio.play(spaceSound2) end
end

return playingState
