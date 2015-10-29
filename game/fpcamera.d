﻿module game.fpcamera;

import derelict.opengl.gl;

import dlib.core.memory;
import dlib.math.vector;
import dlib.math.matrix;
import dlib.math.affine;
import dlib.math.utils;

import dgl.core.interfaces;
import dgl.graphics.camera;

class FirstPersonCamera: Modifier, Camera
{
    Matrix4x4f transformation;
    Matrix4x4f gunTransformation;
    Vector3f position;
    Vector3f eyePosition = Vector3f(0, 0, 0);
    Vector3f gunPosition = Vector3f(0, 0, 0);
    float turn = 0.0f;
    float pitch = 0.0f;
    float roll = 0.0f;
    float gunPitch = 0.0f;
    float gunRoll = 0.0f;
    Matrix4x4f worldTransInv;
    
    this(Vector3f position)
    {
        this.position = position;
    }
    
    Matrix4x4f worldTrans(double dt)
    {  
        Matrix4x4f m = translationMatrix(position + eyePosition);
        m *= rotationMatrix(Axis.y, degtorad(turn));
        m *= rotationMatrix(Axis.x, degtorad(pitch));
        m *= rotationMatrix(Axis.z, degtorad(roll));
        return m;
    }
    
    Matrix4x4f getTransform()
    {
        return transformation;
    }
    
    override void bind(double dt)
    {
        transformation = worldTrans(dt);
        
        gunTransformation = translationMatrix(position + eyePosition);
        gunTransformation *= rotationMatrix(Axis.y, degtorad(turn));
        gunTransformation *= rotationMatrix(Axis.x, degtorad(gunPitch));
        gunTransformation *= rotationMatrix(Axis.z, degtorad(gunRoll));
        gunTransformation *= translationMatrix(gunPosition);
        
        worldTransInv = transformation.inverse;
        glPushMatrix();
        glMultMatrixf(worldTransInv.arrayof.ptr);
    }
    
    override void unbind()
    {
        glPopMatrix();
    }

    void free()
    {
        Delete(this);
    }
}

