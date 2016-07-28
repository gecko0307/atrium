/*
Copyright (c) 2011-2013 Timur Gafarov 

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

module dlib.geometry.ray;

private 
{
    import std.math;
    import dlib.math.vector;
    import dlib.math.utils;
}

public:

struct Ray
{
    Vector3f p0;
    Vector3f p1;
    float t;

    this(Vector3f begin = Vector3f(), Vector3f end = Vector3f())
    {
        p0 = begin;
        p1 = end;
    }

    bool intersectSphere(Vector3f position, float radius, out Vector3f intersectionPoint)
    {
        Vector3f dir = p1 - p0;
        dir.normalize();
        Vector3f dist = position - p0;
        float B = dot(dist,dir);
        float D = radius * radius - dot(dist,dist) + B * B;
        if (D < 0.0f)
        {
            intersectionPoint = Vector3f(0.0f, 0.0f, 0.0f);
            return false;
        }
        float t0 = B - sqrt(D);
        float t1 = B + sqrt(D);
        if (t0 > 0.0f)
        {
            t = t0;
            intersectionPoint = p0 + dir * t0;
            return true;
        }
        if (t1 > 0.0f)
        {
            t = t1;
            intersectionPoint = p0 + dir * t1;
            return true;
        }
        intersectionPoint = Vector3f(0.0f, 0.0f, 0.0f);
        return false;
    }

    bool intersectTriangle(Vector3f v0, Vector3f v1, Vector3f v2, out Vector3f intersectionPoint)
    {
        Vector3f u, v, n;    // triangle vectors
        Vector3f dir, w0, w; // ray vectors
        float r, a, b;       // params to calc ray-plane intersect

        // get triangle edge vectors and plane normal
        u = v1 - v0;
        v = v2 - v0;
        n = cross(u, v); // cross product
        if (n.isZero)    // triangle is degenerate
        {
            intersectionPoint = Vector3f(0.0f, 0.0f, 0.0f);
            return false;
        }

        dir = p1 - p0; // ray direction vector
        w0 = p0 - v0;
        a = -dot(n, w0);
        b = dot(n, dir);

        if (fabs(b) < EPSILON) // ray is parallel to triangle plane
        {
            // no intersect
            intersectionPoint = Vector3f(0.0f, 0.0f, 0.0f);
            return false;
        }

        // get intersect point of ray with triangle plane
        r = a / b;
        if (r < 0.0f) // ray goes away from triangle
        {
            // no intersect
            intersectionPoint = Vector3f(0.0f, 0.0f, 0.0f); 
            return false;
        }

        Vector3f I = p0 + dir * r; // intersect point of ray and plane

        float uu, uv, vv, wu, wv, D;
        uu = dot(u, u);
        uv = dot(u, v);
        vv = dot(v, v);
        w = I - v0;
        wu = dot(w, u);
        wv = dot(w, v);
        D = uv * uv - uu * vv;

        // get and test parametric coords
        float s, t;
        s = (uv * wv - vv * wu) / D;
        if (s < 0.0 || s > 1.0)        // point is outside of the triangle
        {
            intersectionPoint = Vector3f(0.0f, 0.0f, 0.0f);
            return false;
        }
        t = (uv * wu - uu * wv) / D;
        if (t < 0.0 || (s + t) > 1.0)  // point is outside of the triangle
        {
            intersectionPoint = Vector3f(0.0f, 0.0f, 0.0f);
            return false;
        }

        intersectionPoint = I; // point is inside of the triangle
        return true;
    }
}
