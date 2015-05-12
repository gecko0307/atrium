/*
Copyright (c) 2015 Timur Gafarov 

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

module dgl.asset.resman;

import std.stdio;
import std.file;
import dlib.core.memory;
import dlib.container.array;
import dlib.container.aarray;
import dlib.image.io.png;
import dlib.filesystem.filesystem;
import vegan.stdfs;
import vegan.image;
import dgl.core.interfaces;
import dgl.vfs.vfs;
import dgl.graphics.texture;
import dgl.ui.font;
import dgl.graphics.scene;
import dgl.graphics.lightmanager;
import dgl.graphics.shadow;
import dgl.asset.dgl2;

class ResourceManager: ManuallyAllocatable, Drawable
{
    VirtualFileSystem fs;
    VeganImageFactory imgFac;
    AArray!Font fonts;
    AArray!Texture textures;
	
	DynamicArray!Scene _scenes;
	AArray!size_t scenesByName;
    
	LightManager lm;
    ShadowMap shadow;
    bool enableShadows = false;
    
    this()
    {
        fs = New!VirtualFileSystem();
        imgFac = New!VeganImageFactory();
        fonts = New!(AArray!Font)();
        textures = New!(AArray!Texture)();
        scenesByName = New!(AArray!size_t)();
        lm = New!LightManager();
        lm.lightsVisible = true; 
    }

    Font addFont(string name, Font f)
    {
        fonts[name] = f;
        return f;
    }

    Font getFont(string name)
    {
        return fonts[name];
    }

    Texture addTexture(string name, Texture t)
    {
        textures[name] = t;
        return t;
    }
    
    Texture getTexture(string filename)
    {
        if (filename in textures)
            return textures[filename];

        if (!fileExists(filename))
        {
            writefln("Warning: cannot find image file (trying to load \'%s\')", filename);
            return null;
        }
        
        auto fstrm = fs.openForInput(filename);
        auto res = loadPNG(fstrm, imgFac);
        fstrm.free();
        
        if (res[0] is null)
        {
            return null;
        }
        else
        {
            auto tex = New!Texture(res[0]);
            res[0].free();
            return addTexture(filename, tex);
        }
    }

    Scene loadScene(string filename, bool visible = true)
    {
        Scene scene = New!Scene(this);

        scene.clearArrays();
        auto fstrm = fs.openForInput(filename);
        loadDGL2(fstrm, scene);
        fstrm.free();
        scene.resolveLinks();

        scene.visible = visible;
		_scenes.append(scene);
        scenesByName[filename] = _scenes.length;
        return scene;
    }

    Scene addEmptyScene(string name, bool visible = true)
    {
        Scene scene = New!Scene(this);
        scene.visible = visible;
		_scenes.append(scene);
        scenesByName[name] = _scenes.length;
        return scene;
    }

    void freeFonts()
    {
        foreach(i, f; fonts)
            f.free();
        fonts.free();
    }

    void freeTextures()
    {
        foreach(i, t; textures)
            t.free();
        textures.free();
    }

    void freeScenes()
    {
        foreach(i, s; _scenes.data)
            s.free();
        _scenes.free();
		scenesByName.free();
    }
    
    void free()
    {
        Delete(imgFac);
        fs.free();
        freeFonts();
        freeTextures();
        freeScenes();
        lm.free();
        if (shadow !is null)
            shadow.free();
        Delete(this);
    }

    void draw(double dt)
    {
        if (enableShadows && shadow)
            shadow.draw(dt);

        foreach(i, s; _scenes.data)
            if (s.visible)
                s.draw(dt);

        lm.draw(dt);
    }

    bool fileExists(string filename)
    {
        FileStat stat;
        return fs.stat(filename, stat);
    }

    // Don't forget to delete the string!
    string readText(string filename)
    {
        auto fstrm = fs.openForInput(filename);
        string text = .readText(fstrm);
        fstrm.free();
        return text;
    }
    
    mixin ManualModeImpl;
}

