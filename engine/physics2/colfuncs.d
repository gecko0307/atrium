module engine.physics2.colfuncs;

import std.math;
import dlib.math.vector;
import dlib.math.matrix4x4;
import dlib.math.matrix3x3;
import dlib.math.quaternion;

import engine.physics2.geometry;
import engine.physics2.contact;

/*
 * Collisions between various shapes:
 * - sphere/sphere
 * - sphere/box
 * - box/box
 */

bool checkCollisionSphereVsSphere(GeomSphere sphere1, GeomSphere sphere2, ref Contact c)
{
    Vector3f sphere1Pos = sphere1.position;
    Vector3f sphere2Pos = sphere2.position;

    float d = distance(sphere1Pos, sphere2Pos);
    float sumradius = sphere1.radius + sphere2.radius;

    if (d < sumradius)
    {
        c.penetration = sumradius - d;
        c.normal = (sphere1Pos - sphere2Pos).normalized;
        c.point = sphere2Pos + c.normal * sphere2.radius;
        c.fact = true;
        return true;
    }

    return false;
}

bool checkCollisionSphereVsBox(GeomSphere s, GeomBox b, ref Contact c)
{
    Vector3f relativeCenter = s.position - b.position;
    relativeCenter = b.transformation.invRotate(relativeCenter);
    
    if (abs(relativeCenter.x) - s.radius > b.halfSize.x ||
        abs(relativeCenter.y) - s.radius > b.halfSize.y ||
        abs(relativeCenter.z) - s.radius > b.halfSize.z)
        return false;
        
    Vector3f closestPt = Vector3f(0.0f, 0.0f, 0.0f);
    float distance;

    distance = relativeCenter.x;
    if (distance >  b.halfSize.x) distance =  b.halfSize.x;
    if (distance < -b.halfSize.x) distance = -b.halfSize.x;
    closestPt.x = distance;
    
    distance = relativeCenter.y;
    if (distance >  b.halfSize.y) distance =  b.halfSize.y;
    if (distance < -b.halfSize.y) distance = -b.halfSize.y;
    closestPt.y = distance;
    
    distance = relativeCenter.z;
    if (distance >  b.halfSize.z) distance =  b.halfSize.z;
    if (distance < -b.halfSize.z) distance = -b.halfSize.z;
    closestPt.z = distance;
    
    float distanceSqr = (closestPt - relativeCenter).lengthsqr;
    if (distanceSqr > s.radius * s.radius) 
        return false;
        
    Vector3f closestPointWorld = b.transformation.transform(closestPt);
    
    c.fact = true;
    c.normal = -(closestPointWorld - s.position).normalized;
    c.point = closestPointWorld;
    c.penetration = s.radius - sqrt(distanceSqr);
    
    return true;
}

float transformToAxis(
    GeomBox box,
    Vector3f axis)
{
    return
        box.halfSize.x * abs(dot(axis, box.axis(0))) +
        box.halfSize.y * abs(dot(axis, box.axis(1))) +
        box.halfSize.z * abs(dot(axis, box.axis(2)));
}

float penetrationOnAxis(
    GeomBox one,
    GeomBox two,
    Vector3f axis,
    Vector3f toCentre)
{
    // Project the half-size of one onto axis
    float oneProject = transformToAxis(one, axis);
    float twoProject = transformToAxis(two, axis);

    // Project this onto the axis
    float distance = abs(dot(toCentre, axis));

    // Return the overlap (i.e. positive indicates
    // overlap, negative indicates separation).
    return oneProject + twoProject - distance;
}

bool tryAxis(
    GeomBox one,
    GeomBox two,
    Vector3f axis,
    Vector3f toCentre,
    uint index,

    // These values may be updated
    ref float smallestPenetration,
    ref uint smallestCase)
{
    // Make sure we have a normalized axis, and don't check almost parallel axes
    if (axis.lengthsqr < 0.0001f) return true;
    axis.normalize();

    float penetration = penetrationOnAxis(one, two, axis, toCentre);

    if (penetration < 0.0f) return false;

    if (penetration < smallestPenetration)
    {
        smallestPenetration = penetration;
        smallestCase = index;
    }

    return true;
}

void fillPointFaceBoxBox(
    GeomBox one,
    GeomBox two,
    Vector3f toCentre,
    uint best,
    float pen,
    ref Contact contact)
{
    // This method is called when we know that a vertex from
    // box two is in contact with box one.

    // We know which axis the collision is on (i.e. best),
    // but we need to work out which of the two faces on
    // this axis.
    Vector3f normal = one.axis(best);
    if (dot(normal, toCentre) > 0.0f)
    {
        normal = normal * -1.0f;
    }

    // Work out which vertex of box two we're colliding with.
    // Using toCentre doesn't work!
    Vector3f vertex = two.halfSize;
    if (dot(two.axis(0), normal) < 0.0f) vertex.x = -vertex.x;
    if (dot(two.axis(1), normal) < 0.0f) vertex.y = -vertex.y;
    if (dot(two.axis(2), normal) < 0.0f) vertex.z = -vertex.z;

    // Create the contact data
    //Contact contact;
    contact.normal = normal;
    contact.penetration = pen;
    contact.point = two.transformation.transform(vertex);
    contact.fact = true;
}

Vector3f contactPoint(
    Vector3f pOne,
    Vector3f dOne,
    float oneSize,
    Vector3f pTwo,
    Vector3f dTwo,
    float twoSize,
    // If this is true, and the contact point is outside
    // the edge (in the case of an edge-face contact) then
    // we use one's midpoint, otherwise we use two's.
    bool useOne)
{
    Vector3f toSt, cOne, cTwo;
    float dpStaOne, dpStaTwo, dpOneTwo, smOne, smTwo;
    float denom, mua, mub;

    smOne = dOne.lengthsqr;
    smTwo = dTwo.lengthsqr;
    dpOneTwo = dot(dTwo, dOne);

    toSt = pOne - pTwo;
    dpStaOne = dot(dOne, toSt);
    dpStaTwo = dot(dTwo, toSt);

    denom = smOne * smTwo - dpOneTwo * dpOneTwo;

    // Zero denominator indicates parrallel lines
    if (abs(denom) < 0.0001f)
    {
        return useOne? pOne : pTwo;
    }

    mua = (dpOneTwo * dpStaTwo - smTwo * dpStaOne) / denom;
    mub = (smOne * dpStaTwo - dpOneTwo * dpStaOne) / denom;

    // If either of the edges has the nearest point out
    // of bounds, then the edges aren't crossed, we have
    // an edge-face contact. Our point is on the edge, which
    // we know from the useOne parameter.
    if (mua > oneSize ||
        mua < -oneSize ||
        mub > twoSize ||
        mub < -twoSize)
    {
        return useOne? pOne : pTwo;
    }
    else
    {
        cOne = pOne + dOne * mua;
        cTwo = pTwo + dTwo * mub;

        return cOne * 0.5f + cTwo * 0.5f;
    }
}

bool checkCollisionBoxVsBox(GeomBox one, GeomBox two, ref Contact contact)
{
    // Find the vector between the two centres
    Vector3f toCentre = two.position - one.position;

    // We start assuming there is no contact
    float pen = float.max;
    uint best = 0xffffff;

    // Now we check each axes, returning if it gives us
    // a separating axis, and keeping track of the axis with
    // the smallest penetration otherwise.
    if (!tryAxis(one, two, one.axis(0), toCentre, 0, pen, best)) return false;
    if (!tryAxis(one, two, one.axis(1), toCentre, 1, pen, best)) return false;
    if (!tryAxis(one, two, one.axis(2), toCentre, 2, pen, best)) return false;

    if (!tryAxis(one, two, two.axis(0), toCentre, 3, pen, best)) return false;
    if (!tryAxis(one, two, two.axis(1), toCentre, 4, pen, best)) return false;
    if (!tryAxis(one, two, two.axis(2), toCentre, 5, pen, best)) return false;

    // Store the best axis-major, in case we run into almost
    // parallel edge collisions later
    uint bestSingleAxis = best;

    if (!tryAxis(one, two, cross(one.axis(0), two.axis(0)), toCentre, 6, pen, best)) return false;
    if (!tryAxis(one, two, cross(one.axis(0), two.axis(1)), toCentre, 7, pen, best)) return false;
    if (!tryAxis(one, two, cross(one.axis(0), two.axis(2)), toCentre, 8, pen, best)) return false;

    if (!tryAxis(one, two, cross(one.axis(1), two.axis(0)), toCentre, 9, pen, best)) return false;
    if (!tryAxis(one, two, cross(one.axis(1), two.axis(1)), toCentre, 10, pen, best)) return false;
    if (!tryAxis(one, two, cross(one.axis(1), two.axis(2)), toCentre, 11, pen, best)) return false;

    if (!tryAxis(one, two, cross(one.axis(2), two.axis(0)), toCentre, 12, pen, best)) return false;
    if (!tryAxis(one, two, cross(one.axis(2), two.axis(1)), toCentre, 13, pen, best)) return false;
    if (!tryAxis(one, two, cross(one.axis(2), two.axis(2)), toCentre, 14, pen, best)) return false;

    // Make sure we've got a result.
    assert(best != 0xffffff);

    // We now know there's a collision, and we know which
    // of the axes gave the smallest penetration. We now
    // can deal with it in different ways depending on
    // the case.
    if (best < 3)
    {
        // We've got a vertex of box two on a face of box one.
        fillPointFaceBoxBox(one, two, toCentre, best, pen, contact);
        return true;
    }
    else if (best < 6)
    {
        // We've got a vertex of box one on a face of box two.
        // We use the same algorithm as above, but swap around
        // one and two (and therefore also the vector between their
        // centres).
        fillPointFaceBoxBox(two, one, toCentre * -1.0f, best-3, pen, contact);
        contact.normal = -contact.normal;
        return true;
    }
    else
    {
        // We've got an edge-edge contact. Find out which axes
        best -= 6;
        uint oneAxisIndex = best / 3;
        uint twoAxisIndex = best % 3;
        Vector3f oneAxis = one.axis(oneAxisIndex);
        Vector3f twoAxis = two.axis(twoAxisIndex);
        Vector3f axis = cross(oneAxis, twoAxis);
        axis.normalize();

        // The axis should point from box one to box two.
        if (dot(axis, toCentre) > 0.0f)
            axis = axis * -1.0f;

        // We have the axes, but not the edges: each axis has 4 edges parallel
        // to it, we need to find which of the 4 for each object. We do
        // that by finding the point in the centre of the edge. We know
        // its component in the direction of the box's collision axis is zero
        // (its a mid-point) and we determine which of the extremes in each
        // of the other axes is closest.
        Vector3f ptOnOneEdge = one.halfSize;
        Vector3f ptOnTwoEdge = two.halfSize;
        for (uint i = 0; i < 3; i++)
        {
            if (i == oneAxisIndex) ptOnOneEdge[i] = 0;
            else if (dot(one.axis(i), axis) > 0) ptOnOneEdge[i] = -ptOnOneEdge[i];

            if (i == twoAxisIndex) ptOnTwoEdge[i] = 0;
            else if (dot(two.axis(i), axis) < 0) ptOnTwoEdge[i] = -ptOnTwoEdge[i];
        }

        // Move them into world coordinates (they are already oriented
        // correctly, since they have been derived from the axes).
        ptOnOneEdge = one.transformation.transform(ptOnOneEdge);
        ptOnTwoEdge = two.transformation.transform(ptOnTwoEdge);

        // So we have a point and a direction for the colliding edges.
        // We need to find out point of closest approach of the two
        // line-segments.
        Vector3f vertex = contactPoint(
            ptOnOneEdge, oneAxis, one.halfSize[oneAxisIndex],
            ptOnTwoEdge, twoAxis, two.halfSize[twoAxisIndex],
            bestSingleAxis > 2
            );

        // We can fill the contact.
        contact.penetration = pen;
        contact.normal = axis;
        contact.point = vertex;
        contact.fact = true;

        return true;
    }

    return false;
}

