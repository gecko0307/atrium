/*
Copyright (c) 2014-2015 Timur Gafarov 

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

module dgl.core.layer;

import std.stdio;
import std.conv;

import dlib.core.memory;
import dlib.container.array;

import derelict.opengl.gl;
import derelict.opengl.glu;
import derelict.sdl.sdl;

import dgl.core.event;
import dgl.core.interfaces;
import dgl.core.application;

enum LayerType
{
    Layer2D,
    Layer3D
}

class Layer: EventListener, Drawable
{
    LayerType type;
    float aspectRatio;
    
    DynamicArray!Drawable drawables;
    DynamicArray!Modifier modifiers;
        
    this(EventManager emngr, LayerType type)
    {
        super(emngr);
        this.type = type;
        this.aspectRatio = cast(float)emngr.windowWidth / cast(float)emngr.windowHeight;
    }
    
    void addDrawable(Drawable d)
    {
        drawables.append(d);
    }
    
    void addModifier(Modifier m)
    {
        modifiers.append(m);
    }
    
    void draw(double dt)
    {       
        glMatrixMode(GL_PROJECTION);
        glPushMatrix();
        glLoadIdentity();

        if (type == LayerType.Layer2D)
            glOrtho(0, eventManager.windowWidth, 0, eventManager.windowHeight, -1, 1);
        else
            gluPerspective(60, aspectRatio, 0.1, 400.0);
        glMatrixMode(GL_MODELVIEW);
        
        glLoadIdentity();

        foreach(i, m; modifiers.data)
            m.bind(dt);
        foreach(i, drw; drawables.data)
            drw.draw(dt);
        foreach(i, m; modifiers.data)
            m.unbind();
        
        glMatrixMode(GL_PROJECTION);
        glPopMatrix();
        glMatrixMode(GL_MODELVIEW);
    }
    
    void freeContent()
    {
        version (MemoryDebug) writefln("Deleting %s drawable(s) in layer...", drawables.length);
        foreach(i, drw; drawables.data)
            drw.free();
        drawables.free();
    }
    
    override void free()
    {
        freeContent();
        Delete(this);
    }
    
    override void onResize(int width, int height)
    {
        writefln("Layer received resize event: %s x %s", width, height);
        aspectRatio = cast(float)width / cast(float)height;
    }
}
