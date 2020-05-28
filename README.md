love-loader
===========

This is an utility lib for [LÖVE](http://love2d.org) that loads
resources (images, sounds) from the hard disk on a separate thread.

This allows for "doing stuff" while resources are being loaded; for
example, playing an animation. The fact that the blocking calls happen
in a separate thread ensures that the animation is fluid, without
blocking calls dropping the framerate.

Version 2.0.0 of this lib only works with LÖVE 0.9.x. If you need to
work with LÖVE 0.8 or before, please use earlier versions of this lib.

This repository is maintained by Tanner Rogalsky (https://github.com/TannerRogalsky).

Example
=======

```lua
local loader = require 'love-loader'

local images = {}
local sounds = {}

local finishedLoading = false

function love.load()
  loader.newImage(  images, 'rabbit', 'path/to/rabbit.png')
  loader.newSource( sounds, 'iiiik',  'path/to/iiik.ogg', 'static')
  loader.newSource( sounds, 'music',  'path/to/music.ogg', 'stream')

  loader.start(function()
    finishedLoading = true
  end)
end

function love.update(dt)
  if not finishedLoading then
    loader.update() -- You must do this on each iteration until all resources are loaded
  end
end

function love.draw()
  if finishedLoading then
    -- media contains the images and sounds. You can use them here safely now.
    love.graphics.draw(images.rabbit, 100, 200)
  else -- not finishedLoading
    local percent = 0
    if loader.resourceCount ~= 0 then percent = loader.loadedCount / loader.resourceCount end
    love.graphics.print(("Loading .. %d%%"):format(percent*100), 100, 100)
  end
end
```

You can also see a working demo in the
[demo branch of this repo](https://github.com/kikito/love-loader/tree/demo).

Interface
=========

* `loader.newImage(holder, key, path)`. Adds a new image to the list
  of images to load.
* `loader.newSource(holder, key, path, sourceType)`. Adds a new source
  to the list of sources to load.
* `loader.newFont(holder, key, path)`. Adds a new font to the list of
  fonts to load.
* `loader.start(finishCallback, loadedCallback)`. Starts doing the
  loading on a separate thread. When it finishes, it invokes
  `finishCallback` with no parameters. Every time it loads a new
  resource, it invokes `loadedCallback`. `finishedCallback` admits no
  parameters, and `loadedCallback`'s signature is
  `function(kind, holder, key)`. `kind` is a string ("image", "source"
  or "stream"). Neither `loadedCallback` or `finishedCallback` are
  mandatory.
* `loader.loadedCount` integer returning the number of resources
  loaded. When `loader.start` gets invoked, it's 0.
* `loader.resourceCount` integer containing the total number of
  resources to be loaded. It can be used in conjunction with
  `loader.loadedCount` to show progressbars etc.

Installation
============

Just copy the love-loader.lua file somewhere in your projects (maybe
inside a /lib/ folder) and require it accordingly.

Remember to store the value returned by require somewhere! (I suggest a
local variable named `loader` or `love.loader`)

```lua
local loader = require 'love-loader'
```

The second step is making sure that your "game loop" calls
`loader.update`, at least while there are resources to load.

License
=======

This library is distributed under the MIT License.

Credits
=======

I took a lot of inspiration from Michael Enger's Stealth2D project. I
learned the basic internals of threads from his loading state code.

https://github.com/michaelenger/Stealth2D

Tanner Rogalsky (https://github.com/TannerRogalsky) ported the library
to LÖVE 0.9.0.
