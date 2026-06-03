# Ruby Cards

A card game engine for playing various card games designed using Ruby's Gosu library. Games are written as .json files which currently need to be written by hand but will have a program to produce them in the future.

## Client
For connecting to the Ruby Cards server of your choice, though currently only tries to connect to a server running on `localhost:25252`

### Running

#### Windows

Download the Windows executable from releases. As long as you have the server running on your local machine, running it will connect and try to play the hearts game

#### Linux

It's easier to get this stuff installed and running on linux, so it's not packaged. You need to pull down the source code and make sure your dependencies are installed (ruby 3.x, the libraries referenced below). Then `bundle install`. From within `client/src/client` run `bundle exec ruby game_client.rb`

### Gem Dependencies

#### gosu
Requires sdl libraries

The following libraries meet all the requirements (though might be excessive), at least on Ubuntu 22:

build-essential xorg-dev libudev-dev libts-dev libgl1-mesa-dev libglu1-mesa-dev libasound2-dev libpulse-dev libopenal-dev libogg-dev libvorbis-dev libaudiofile-dev libpng12-dev libfreetype6-dev libusb-dev libdbus-1-dev zlib1g-dev libdirectfb-dev

## Server

Runs the card game (currently only Hearts) on `localhost:25252` for clients to connect to.

### Running

#### Windows

Download the Windows executable from releases and run it. It should indicate it's running the server.

#### Linux

It's easier to get this stuff installed and running on linux, so it's not packaged. You need to pull down the source code and make sure your dependencies are installed (ruby 3.x). Then `bundle install`. From within `server/src` run `bundle exec ruby server.rb`