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

module dgl.graphics.entity;

import dlib.math.vector;
import dlib.math.matrix;
import dlib.math.affine;
import dlib.math.quaternion;
import dgl.core.api;
import dgl.core.interfaces;
import dgl.graphics.material;
import dgl.graphics.light;
import dgl.text.dml;

class Entity: Drawable
{
    Light[maxLightsPerObject] lights;
    uint numLights = 0;

    Matrix4x4f transformation;
    Vector3f position;
    Quaternionf rotation;
    Vector3f scaling;
    bool autoUpdateTransformation = true;

    Drawable model;
    Material material;
    bool shadeless = false;
    bool visible = true;
    bool transparent = false;

    uint id;
    uint type = 0;
    uint materialID = -1;
    uint meshID = -1;
    uint groupID = 0;
    
    DMLData props;

    this(Drawable d = null)
    {
        position = Vector3f(0, 0, 0);
        rotation = Quaternionf.identity;
        scaling = Vector3f(1, 1, 1);
        transformation = 
            translationMatrix(position) *
            rotation.toMatrix4x4 *
            scaleMatrix(scaling);
        model = d;
    }
    
    Vector3f getPosition()
    {
        return position;
    }
    
    Quaternionf getRotation()
    {
        return rotation;
    }
    
    Vector3f getScaling()
    {
        return position;
    }
    
    Matrix4x4f getTransformation()
    {
        return transformation;
    }
    
    ~this()
    {
        props.free();
    }
    
    void setTransformation(Vector3f pos, Quaternionf rot, Vector3f scal)
    {
        position = pos;
        rotation = rot;
        scaling = scal;
        
        transformation = 
            translationMatrix(position) *
            rotation.toMatrix4x4 *
            scaleMatrix(scaling);
    }

    void update(double dt)
    {
        if (autoUpdateTransformation)
        {
            transformation = 
                translationMatrix(position) *
                rotation.toMatrix4x4 *
                scaleMatrix(scaling);
        }
    }

    void draw(double dt)
    {
        if (visible)
        {
            glPushMatrix();
            glMultMatrixf(transformation.arrayof.ptr);                    
            drawModel(dt);                   
            glPopMatrix();
        }
    }

    void drawModel(double dt)
    {
        if (material)
            material.bind(dt);

        if (model !is null)
            model.draw(dt);

        if (material)
            material.unbind();
    }
}
