Atrium
======
The goal of this project is to create a first-person shooter with physics based puzzles, entirely in [D language](http://dlang.org).

Visit the project site at http://gecko0307.github.io/atrium

Also visit our [IndieDB page](http://www.indiedb.com/games/atrium) and follow the development blog (in Russian) at http://dlanggamedev.blogspot.ru

Screenshots
-----------
[![Screenshot1](/screenshots/011_thumb.jpg)](/screenshots/011.jpg)
[![Screenshot1](/screenshots/012_thumb.jpg)](/screenshots/012.jpg)

Gameplay
--------
Atrium will provide high level of interactivity, featuring fully dynamic world with everything being controlled by the physics engine. You will be able to walk on any surface and push any object, use special devices to affect gravity and other physical behaviours of the environment. The gameplay will be peaceful and non-violent: explore the world, solve the puzzles and unleash the mysteries.

Tech details
------------
Atrium uses OpenGL for rendering, thus (theoretically) supporting all platforms that provide OpenGL API. Main target platforms are Windows and Linux. Currently Atrium is tested and known to work on Linux, Windows (XP and above), OSX and FreeBSD, both 32 and 64 bit.

The game features [modern graphics engine](https://github.com/gecko0307/dgl) with smooth shadows, dynamic shader-based lighting and material system, anti-aliasing and Full HD rendering. Atrium also utilizes [its own physics engine](https://github.com/gecko0307/dmech), that was specifically written for this project.

Download
--------
The project is still far from being finished, but you already can give it a shot: download a recent tech demo for your OS from [here](https://www.dropbox.com/sh/mmh9qod4x2nsuyi/66ZW6KX7N6).

Build from source
-----------------
The project is written in D2 using Phobos and requires up-to-date D compiler (DMD or LDC). To build Atrium, follow the instructions in the INSTALL file.
