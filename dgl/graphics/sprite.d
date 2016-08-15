/*
Copyright (c) 2015-2016 Timur Gafarov

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

module dgl.graphics.sprite;

import dlib.core.memory;
import dlib.image.color;
import dlib.math.vector;
import dgl.core.api;
import dgl.core.event;
import dgl.core.interfaces;
import dgl.graphics.texture;
import dgl.graphics.material;

// TODO: make all these children of one Sprite class

class ScreenSprite: EventListener, Drawable
{
    Material material;

    this(EventManager em, Texture tex)
    {
        super(em);
        material = New!Material();
        material.shadeless = true;
        material.textures[0] = tex;
    }

    override void draw(double dt)
    {
        //glDisable(GL_MULTISAMPLE_ARB);
        material.bind(dt);
        glDepthMask(0);
        glColor4f(1, 1, 1, 1);
        glBegin(GL_QUADS);
        glTexCoord2f(0, 0); glVertex2f(0, 0);
        glTexCoord2f(1, 0); glVertex2f(eventManager.windowWidth, 0);
        glTexCoord2f(1, 1); glVertex2f(eventManager.windowWidth, eventManager.windowHeight);
        glTexCoord2f(0, 1); glVertex2f(0, eventManager.windowHeight);
        glEnd();
        glDepthMask(1);
        material.unbind();
        //glEnable(GL_MULTISAMPLE_ARB);
    }

    ~this()
    {
        Delete(material);
    }
}

class Sprite: Drawable
{
    Texture texture;
    uint width;
    uint height;
    Vector2f position;
    Color4f color;

    this(Texture tex, uint w, uint h)
    {
        texture = tex;
        width = w;
        height = h;
        position = Vector2f(0, 0);
        color = Color4f(1,1,1,1);
    }

    void draw(double dt)
    {
        glDepthMask(0);
        glDisable(GL_DEPTH_TEST);
        glDisable(GL_LIGHTING);
        glPushMatrix();
        glColor4fv(color.arrayof.ptr);
        glTranslatef(position.x, position.y, 0.0f);
        glScalef(width, height, 1.0f);
        texture.bind(dt);
        glBegin(GL_QUADS);
        glTexCoord2f(0, 0); glVertex2f(0, 1);
        glTexCoord2f(0, 1); glVertex2f(0, 0);
        glTexCoord2f(1, 1); glVertex2f(1, 0);
        glTexCoord2f(1, 0); glVertex2f(1, 1);
        glEnd();
        texture.unbind();
        glPopMatrix();
        glEnable(GL_DEPTH_TEST);
        glDepthMask(1);
    }

    ~this()
    {
    }
}

class AnimatedSprite: Drawable
{
    Texture texture;
    uint tileWidth;
    uint tileHeight;
    uint tx = 0;
    uint ty = 0;
    uint numHTiles;
    uint numVTiles;
    float framerate = 1.0f / 25.0f;
    double counter = 0.0;
    Vector2f position;

    this(Texture sheetTex, uint w, uint h)
    {
        texture = sheetTex;
        tileWidth = w;
        tileHeight = h;
        numHTiles = texture.width / tileWidth;
        numVTiles = texture.height / tileHeight;
        position = Vector2f(0, 0);
    }

    void draw(double dt)
    {
        counter += dt;
        if (counter >= framerate)
        {
            counter = 0.0;
            advanceFrame();
        }

        float u = cast(float)(tx * tileWidth) / texture.width;
        float v = cast(float)(ty * tileHeight) / texture.height;
        float w = cast(float)tileWidth / texture.width;
        float h = cast(float)tileHeight / texture.height;

        glDepthMask(0);
        glDisable(GL_DEPTH_TEST);
        glPushMatrix();
        glColor4f(1,1,1,1);
        glTranslatef(position.x, position.y, 0.0f);
        glScalef(tileWidth, tileHeight, 1.0f);
        texture.bind(dt);
        glBegin(GL_QUADS);
        glTexCoord2f(u, v + h);     glVertex2f(0, 0);
        glTexCoord2f(u + w, v + h); glVertex2f(1, 0);
        glTexCoord2f(u + w, v);     glVertex2f(1, 1);
        glTexCoord2f(u, v);         glVertex2f(0, 1);
        glEnd();
        texture.unbind();
        glPopMatrix();
        glEnable(GL_DEPTH_TEST);
        glDepthMask(1);
    }

    void advanceFrame()
    {
        tx++;
        if (tx >= numHTiles)
        {
            tx = 0;
            ty++;

            if (ty >= numVTiles)
            {
                ty = 0;
            }
        }
    }

    ~this()
    {
    }
}
