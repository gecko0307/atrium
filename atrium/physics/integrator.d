/*
Copyright (c) 2013 Timur Gafarov 

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

module atrium.physics.integrator;

private
{
    import std.math;
    import dlib.math.vector;
    import dlib.math.quaternion;
    import atrium.physics.rigidbody;
}

class Euler
{
    static void integrateVelocities(RigidBody b, double dt)
    {        
        b.linearAcceleration = b.forceAccumulator * b.invMass;
        b.linearVelocity += b.linearAcceleration * dt;

        //b.angularAcceleration = b.invInertiaTensor.transform(b.torqueAccumulator); 
        b.angularAcceleration = b.torqueAccumulator * b.invInertiaMoment;
        b.angularVelocity += b.angularAcceleration * dt;
    }

    static void integratePositionAndOrientation(RigidBody b, double dt)
    {
        b.linearVelocity.x *= b.dampingFactor;
        b.linearVelocity.z *= b.dampingFactor;
        b.angularVelocity *= b.dampingFactor;

        b.position += b.linearVelocity * dt;        
        b.orientation += 0.5f * Quaternionf(b.angularVelocity, 0.0f) * b.orientation * dt;
        b.orientation.normalize();
    }
    
    static void integrate(RigidBody b, double dt)
    {
        b.linearAcceleration = b.forceAccumulator * b.invMass;
        b.linearVelocity += b.linearAcceleration * dt;
        //b.angularAcceleration = b.invInertiaTensor.transform(b.torqueAccumulator); 
        b.angularAcceleration = b.torqueAccumulator * b.invInertiaMoment;
        b.angularVelocity += b.angularAcceleration * dt;
        
        b.position += b.linearVelocity * dt;
        
        b.orientation += 0.5f * Quaternionf(b.angularVelocity, 0.0f) * b.orientation * dt;
        b.orientation.normalize();
    }
}

/*
class Verlet
{
    static void integrate(RigidBody b, double dt)
    { 
        b.linearAcceleration = b.forceAccumulator * b.invMass;
        Vector3f oldLinearVelocity = b.linearVelocity;
        b.linearVelocity += b.linearAcceleration * dt;
        b.position += (oldLinearVelocity + b.linearVelocity) * 0.5f * dt;
        
        b.angularAcceleration = b.invInertiaTensor.transform(b.torqueAccumulator); 
        //b.angularAcceleration = b.torqueAccumulator * b.invInertiaMoment;
        b.angularVelocity += b.angularAcceleration * dt;
        b.orientation += 0.5f * Quaternionf(b.angularVelocity, 0.0f) * b.orientation * dt;
        b.orientation.normalize();
    }
}
*/


