/*
Copyright (c) 2014-2016 Timur Gafarov, Andrew Benton, Tanel Tagavali

Boost Software License - Version 1.0 - August 17th, 2003

Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
*/

module dgl.core.application;

import std.stdio;
import std.conv;
import std.process;
import std.string;
import std.file;

import dlib.core.memory;
import dlib.container.dict;
import dlib.image.color;

import derelict.opengl.gl;
import derelict.opengl.glu;
import derelict.sdl.sdl;
import derelict.freetype.ft;
import derelict.openal.al;

import dgl.core.interfaces;
import dgl.core.event;
//import dgl.text.dml;
//import dgl.text.stringconv;
import dgl.asset.props;
import dgl.graphics.material;

/*
 * Basic SDL/OpenGL application.
 * GC-free, but may throw on initialization failure
 */
abstract class Application: EventListener
{
    static
    {
        uint passWidth;
        uint passHeight;
        bool passMaterialsActive = true;
    }

    this()
    {
        uint width = config["videoWidth"].toUInt;
        uint height = config["videoHeight"].toUInt;
        string caption = config["windowCaption"].toString;
        bool unicodeInput = true;
        bool resizableWindow = config["windowResizable"].toBool;
        bool fullscreen = !config["videoWindowed"].toBool;
        bool vsync = config["videoVSync"].toBool;
        bool aa = config["videoAntialiasing"].toBool;
        
        if (SDL_Init(SDL_INIT_EVERYTHING) < 0)
            throw new Exception("Failed to init SDL: " ~ to!string(SDL_GetError()));

        SDL_EnableUNICODE(unicodeInput);

        SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
        SDL_GL_SetAttribute(SDL_GL_RED_SIZE, 5);
        SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE, 5);
        SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE, 5);
        SDL_GL_SetAttribute(SDL_GL_BUFFER_SIZE, 32);
        SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 16);
        if (vsync)
            SDL_GL_SetAttribute(SDL_GL_SWAP_CONTROL, 1);
        else
            SDL_GL_SetAttribute(SDL_GL_SWAP_CONTROL, 0);
        if (aa)
        {
            SDL_GL_SetAttribute(SDL_GL_MULTISAMPLEBUFFERS, 1);
            SDL_GL_SetAttribute(SDL_GL_MULTISAMPLESAMPLES, 4);
        }

        if (!fullscreen)
        {
            environment["SDL_VIDEO_WINDOW_POS"] = "";
            environment["SDL_VIDEO_CENTERED"] = "1";
        }
        
        SDL_Surface* screen;
        if (fullscreen)
            screen = SDL_SetVideoMode(width, height, 0, SDL_OPENGL | SDL_FULLSCREEN);
        else if (resizableWindow)
            screen = SDL_SetVideoMode(width, height, 0, SDL_OPENGL | SDL_RESIZABLE);
        else
            screen = SDL_SetVideoMode(width, height, 0, SDL_OPENGL);
        if (screen is null)
            throw new Exception("Failed to set video mode: " ~ to!string(SDL_GetError()));

        SDL_WM_SetCaption(toStringz(caption), null);

        DerelictGL.loadClassicVersions(GLVersion.GL12);
        DerelictGL.loadBasicExtensions();

        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        glEnable(GL_BLEND);
        glEnable(GL_NORMALIZE);
        glShadeModel(GL_SMOOTH);
        glAlphaFunc(GL_GREATER, 0.0);
        glEnable(GL_ALPHA_TEST);
        glEnable(GL_DEPTH_TEST);
        glDepthFunc(GL_LEQUAL);
        glEnable(GL_CULL_FACE);
        glEnable(GL_SCISSOR_TEST);
        
        if (aa)
        {
            glEnable(GL_MULTISAMPLE);
            glHint(GL_LINE_SMOOTH_HINT, GL_NICEST);
            glHint(GL_POLYGON_SMOOTH_HINT, GL_NICEST);
            glEnable(GL_LINE_SMOOTH);
            glEnable(GL_POLYGON_SMOOTH);
        }

        glViewport(0, 0, width, height);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        EventManager emngr = New!EventManager(width, height);
        super(emngr);
    }

    void run()
    {
        while(eventManager.running)
        {
            eventManager.update();
            processEvents();

            glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
            glViewport(0, 0, windowWidth, windowHeight);
            glScissor(0, 0, windowWidth, windowHeight);
            glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

            onUpdate(eventManager.deltaTime);
            onRedraw(eventManager.deltaTime);

            SDL_GL_SwapBuffers();
        }

        SDL_Quit();
    }

    // Override me
    void onUpdate(double dt) {}

    // Override me
    void onRedraw(double dt) {}

    void exit()
    {
        eventManager.running = false;
        onQuit();
    }

    override void onResize(int width, int height)
    {
        SDL_Surface* screen = SDL_SetVideoMode(width,
                                               height,
                                               0, SDL_OPENGL | SDL_RESIZABLE);
        if (screen is null)
            throw new Exception("failed to set video mode: " ~ to!string(SDL_GetError()));
    }

    uint windowWidth()
    {
        return eventManager.windowWidth;
    }

    uint windowHeight()
    {
        return eventManager.windowHeight;
    }

    ~this()
    {
        Delete(eventManager);
    }
}

__gshared Properties config;

void initDGL()
{
    import core.stdc.stdlib : getenv;

    DerelictGL.load();
    DerelictGLU.load();

    version(Windows)
    {
        version(X86)
        {
            DerelictSDL.load("lib/SDL.dll");
            DerelictFT.load("lib/freetype.dll");
            DerelictAL.load("lib/OpenAL32.dll");
        }
        version(X86_64)
        {
            DerelictSDL.load("lib64/SDL64.dll");
            DerelictFT.load("lib64/freetype64.dll");
            DerelictAL.load("lib64/OpenAL64.dll");
        }
    }
    version(linux)
    {
        if(envVarIsTrue(getenv("USE_SYSTEM_LIBS").to!string))
        {
            DerelictSDL.load();
            DerelictFT.load();
            DerelictAL.load();
        }
        else
        {
            version(X86)
            {
                DerelictSDL.load("./lib/libsdl.so");
                DerelictFT.load("./lib/libfreetype.so");
                DerelictAL.load("./lib/libopenal.so.1.14.0");
            }
            version(X86_64)
            {
                DerelictSDL.load("./lib64/libsdl_64.so");
                DerelictFT.load("./lib64/libfreetype_64.so");
                DerelictAL.load();
            }
        }
    }
    version(FreeBSD)
    {
        DerelictSDL.load();
        DerelictFT.load();
        DerelictAL.load();
    }
    version(OSX)
    {
        DerelictSDL.load();
        DerelictFT.load();
        DerelictAL.load();
    }

    string defaultConfig = q{
        videoWidth: 1280;
        videoHeight: 720;
        videoWindowed: 1;
        videoVSync: 0;
        videoAntialiasing: 1;
        
        windowCaption: "DGL application";
        windowResizable: 1;

        fxShadersEnabled: 1;
        fxShadowEnabled: 1;
        fxShadowMapSize: 512;
    };

    config = New!Properties;
    config.parse(defaultConfig);

    if (exists("game.conf"))
    {
        if (!config.parse(readText("game.conf")))
            writeln("Failed to read config \"game.conf\"");
    }
    else
        writeln("Failed to read config \"game.conf\"");}

bool configIsTrue(string key)
{
    if (key in config)
        return config[key].toBool;
    else
        return false;
}

void deinitDGL() 
{
    Delete(config);
    //freeGlobalStringArray();
    Material.deleteUberShader();
}

bool envVarIsTrue(string var)
{
    import std.string : strip;
    import std.uni : toLower;
    if(var == null)
        return false;
    var = var.strip();
    if(var == null)
        return false;
    var = var.toLower!string;
    if(var == "1")
        return true;
    if(var == "true")
        return true;
    return false;
}
