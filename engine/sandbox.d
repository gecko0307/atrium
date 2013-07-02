module engine.sandbox;

import std.math;
import std.stdio;
import std.conv;
import std.algorithm;

import derelict.sdl.sdl;
import derelict.opengl.gl;
import derelict.opengl.glu;

import dlib.math.vector;
import dlib.math.matrix4x4;
import dlib.math.quaternion;
import dlib.math.utils;

import dlib.geometry.triangle;
import dlib.geometry.ray;

import dlib.image.color;
import dlib.image.io.png;

import engine.logic;
import engine.ui.text;

import engine.core.drawable;
import engine.graphics.material;
import engine.graphics.texture;

import engine.scene.scenenode;
import engine.scene.tbcamera;
import engine.scene.primitives;
import engine.scene.bvh;

import engine.physics2.geometry;
import engine.physics2.rigidbody;
import engine.physics2.world;

import engine.glgeom;
import engine.dat;
import engine.fgroup;

Vector2f lissajousCurve(float t)
{
    return Vector2f(sin(t), cos(2 * t));
}

void drawQuad(float width, float height)
{
    glBegin(GL_QUADS);
    glTexCoord2f(0,1); glVertex2f(-width*0.5f, -height*0.5f); 
    glTexCoord2f(0,0); glVertex2f(-width*0.5f, +height*0.5f);
    glTexCoord2f(1,0); glVertex2f(+width*0.5f, +height*0.5f);
    glTexCoord2f(1,1); glVertex2f(+width*0.5f, -height*0.5f);
    glEnd();
}

final class Weapon: SceneNode
{
    DatObject datobj;
    FaceGroup[int] fgroups;
    
    this(string filename, SceneNode par = null)
    {
        super(par);
        datobj = new DatObject(filename);
        fgroups = createFGroups(datobj);
    }
    
    override void render(double delta)
    {
        foreach(fgroup; fgroups)
            glCallList(fgroup.displayList);
    }
}

class SandboxObject: GameObject
{
    TrackballCamera tbcamera;
    int tempMouseX = 0;
    int tempMouseY = 0;
    
    Text txtFPS;
    
    Vector4f lightPos = Vector4f(10.0f, 20.0f, 5.0f, 0.0f);
    
    SceneNode scene;
    
    GeomSphere playerGeometry;
    SceneNode player;
    SceneNode gravityPivot;
    SceneNode cameraPivot;
    SceneNode gravityGunPivot2;
    SceneNode camera;
    SceneNode smoothCam;
    enum playerGrav = 0.2f;
    bool jumped = false;
    bool playerWalking = false;

    PhysicsWorld world;
    
    DatObject levelData;
    BVHTree levelBVH;
    
    // triangle groups by material index
    FaceGroup[int] levelFGroups;

    SceneNode gravityGunPivot;
    Weapon gravityGun;
    float gunSwayTime = 0.0f;
    RigidBody shootedBody = null;

    Texture crosshair;

    T addGeom(T)(T geom)
    {
        matObj ~= geom;
        return geom;
    }
    
    this(GameLogicManager m)
    {
        super(m);

        txtFPS = new Text(logic.fontMain);
        txtFPS.setPos(16, 16);
        
        tbcamera = new TrackballCamera();
        tbcamera.pitch(45.0f);
        tbcamera.turn(45.0f);
        tbcamera.setZoom(20.0f);
        
        world = new PhysicsWorld();

        scene = new SceneNode();
        
        levelData = new DatObject("data/levels/area1/area1.dat");
        levelBVH = new BVHTree(levelData.tris, 1);
        levelFGroups = createFGroups(levelData);
        
        RigidBody playerBody = world.addDynamicBody(levelData.spawnPosition, 80.0f);
        playerGeometry = new GeomSphere(0.75f);
        playerBody.setGeometry(playerGeometry);
        playerBody.disableRotation = true;
        playerBody.dampingFactor = 0.995f;

        player = new SceneNode(scene);
        player.rigidBody = playerBody;

        gravityPivot = new SceneNode(player);
        gravQuat = identityQuaternion!float;
        gravMatrix = identityMatrix4x4f;
        gravityPivot.localMatrixPtr = &gravMatrix;

        cameraPivot = new SceneNode(gravityPivot);
        cameraPivot.rotation.x = radtodeg(levelData.spawnRotation.x);
        cameraPivot.rotation.y = radtodeg(levelData.spawnRotation.y) - 90.0f;
        cameraPivot.rotation.z = radtodeg(levelData.spawnRotation.z);

        camera = new SceneNode(cameraPivot);
        camera.position = Vector3f(0.0f, 0.5f, 0.0f);
        
        smoothCam = new SceneNode(cameraPivot);
        smoothCam.position = Vector3f(0.0f, 0.5f, 0.0f);

        gravityGunPivot = new SceneNode(scene);
        gravityGun = new Weapon("data/weapons/gravitygun/gravitygun.dat", gravityGunPivot);
        
        foreach(orb; levelData.orbs)
        {
            RigidBody rb = world.addDynamicBody(orb.position, 1000.0f);
            rb.setGeometry(new GeomBox(Vector3f(0.5f, 0.5f, 0.5f)));
            PrimBox prim = new PrimBox(Vector3f(0.5f, 0.5f, 0.5f), scene);
            prim.rigidBody = rb;
        }
        
        world.bvhRoot = levelBVH.root;

        crosshair = new Texture(loadPNG("data/weapons/crosshair.png"), false);

        SDL_WarpMouse(cast(ushort)manager.window_width/2, 
                      cast(ushort)manager.window_height/2);
    }
    
    override void onKeyDown()
    {
        if (manager.event_key == SDLK_ESCAPE)
        {
            logic.goToRoom("pauseMenu", false, false);
        }
    }
    
    override void onMouseButtonDown()
    {
        if (manager.event_button == SDL_BUTTON_RIGHT) 
        {
            tempMouseX = manager.mouse_x;
            tempMouseY = manager.mouse_y;
            SDL_WarpMouse(cast(ushort)manager.window_width/2, 
                          cast(ushort)manager.window_height/2);
        }
        else if (manager.event_button == SDL_BUTTON_LEFT) 
        {
            //Vector3f forwardVec = camera.absoluteMatrix.forward;
            //Ray shootRay = Ray(
            //    camera.absoluteMatrix.translation, 
            //    camera.absoluteMatrix.translation - forwardVec * 1000.0f);
            //Vector3f n = (shootRay.p1 - shootRay.p0).normalized;
            //world.gravity = n * 9.81f;
        }
        else if (manager.event_button == SDL_BUTTON_MIDDLE) 
        {
            tempMouseX = manager.mouse_x;
            tempMouseY = manager.mouse_y;
            SDL_WarpMouse(cast(ushort)manager.window_width/2, 
                          cast(ushort)manager.window_height/2);
        }
        else if (manager.event_button == SDL_BUTTON_WHEELUP) 
        {
            tbcamera.zoomSmooth(-2.0f, 16.0f);
        }
        else if (manager.event_button == SDL_BUTTON_WHEELDOWN) 
        {
            tbcamera.zoomSmooth(2.0f, 16.0f);
        }
    }

    void drawFGroups(FaceGroup[int] fgroups)
    {
        foreach(fgroup; fgroups)
            glCallList(fgroup.displayList);
    }

    Quaternionf quaternionBetweenVectors(Vector3f v1, Vector3f v2)
    {
        Quaternionf q;
        Vector3f a = cross(v1, v2);
        q.x = a.x;
        q.y = a.y;
        q.z = a.z;
        q.w = sqrt(v1.lengthsqr * v2.lengthsqr) + dot(v1, v2);
        return q;
    }

    Matrix4x4f gravMatrix;
    Quaternionf gravQuat;
    
    override void onDraw(double delta)
    {
        SDL_ShowCursor(0);
        
        // Camera control
        float turn_m =   (cast(float)(manager.window_width/2 - manager.mouse_x))/10.0f;
        float pitch_m = -(cast(float)(manager.window_height/2 - manager.mouse_y))/10.0f;
        camera.rotation.x += pitch_m;
        cameraPivot.rotation.y += turn_m;
        smoothCam.rotation.x += pitch_m * 0.85f;
        SDL_WarpMouse(cast(ushort)manager.window_width/2, 
                      cast(ushort)manager.window_height/2);
        
        // Player movement            
        player.rigidBody.dampingFactor = 
            max(0.99f, 
                abs(dot(player.rigidBody.linearVelocity.normalized, 
                        world.gravity.normalized)));
            
        playerWalking = false; 

        if (manager.key_pressed['w'])
        {
            player.rigidBody.applyForce(-cameraPivot.absoluteMatrix.forward * 5000.0f);
            if (player.rigidBody.onGround)
                playerWalking = true;
        }

        if (manager.key_pressed['s'])
        {
            player.rigidBody.applyForce(cameraPivot.absoluteMatrix.forward * 5000.0f);
            if (player.rigidBody.onGround)
                playerWalking = true;
        }

        if (manager.key_pressed['a'])
        {
            player.rigidBody.applyForce(-cameraPivot.absoluteMatrix.right * 5000.0f);
            if (player.rigidBody.onGround)
                playerWalking = true;
        }

        if (manager.key_pressed['d'])
        {
            player.rigidBody.applyForce(cameraPivot.absoluteMatrix.right * 5000.0f);
            if (player.rigidBody.onGround)
                playerWalking = true;
        }

        if (manager.key_pressed[SDLK_SPACE])
        {
            if (!jumped)
            {
                if (player.rigidBody.onGround)
                {
                    player.rigidBody.applyForce(-world.gravity.normalized * 30000.0f);
                    player.rigidBody.onGround = false;
                    jumped = true;
                }
            }
        }
        else jumped = false;

        if (manager.key_pressed[SDLK_RETURN])
        {
            gravQuat = dlib.math.quaternion.rotation(Vector3f(1.0f, 0.0f, 0.0f), degtorad(1.0f));
            world.gravity = gravQuat.rotate(world.gravity);

            gravMatrix *= gravQuat.toMatrix();
        }

        // Shoot
        shootWithGravityRay(600.0f);

        // Update physics                   
        world.update(manager.deltaTime);

        // Render
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        glLoadIdentity();
        
        Matrix4x4f camMatrixInv = camera.absoluteMatrix.inverse;
        glPushMatrix();
        glMultMatrixf(camMatrixInv.arrayof.ptr);
        
        glLightfv(GL_LIGHT0, GL_POSITION, lightPos.arrayof.ptr);
        
        // Draw level
        drawFGroups(levelFGroups);

        Matrix4x4f camMatrix = smoothCam.absoluteMatrix;
        camMatrix *= translationMatrix(Vector3f(0.08f, -0.1f, -0.2f));
        camMatrix *= scaleMatrix(Vector3f(0.05f, 0.05f, 0.05f));
        gravityGunPivot.localMatrixPtr = &camMatrix;

        if (playerWalking)
            gunSwayTime += 10.0f * manager.deltaTime;
        else
            gunSwayTime += 1.0f * manager.deltaTime;
            
        if (gunSwayTime > 2 * PI)
            gunSwayTime = 0.0f;
        Vector2f gunSway = lissajousCurve(gunSwayTime) / 10.0f;
        
        gravityGun.position = Vector3f(gunSway.x, gunSway.y, 0.0f);
        if (playerWalking)
        {
            camera.position = Vector3f(gunSway.x, 0.5f + gunSway.y, 0.0f);
            camera.rotation.z = -gunSway.x * 5.0f;
            smoothCam.position = Vector3f(gunSway.x, 0.5f + gunSway.y, 0.0f);
            smoothCam.rotation.z = -gunSway.x * 5.0f;
        }
        
        scene.draw(manager.deltaTime);

        glPopMatrix();
        
        // 2D mode
        glMatrixMode(GL_PROJECTION);
        glPushMatrix();
        glLoadIdentity();
        glOrtho(0, manager.window_width, 0, manager.window_height, -1, 1);
        glMatrixMode(GL_MODELVIEW);

        glLoadIdentity();

        glDisable(GL_LIGHTING);
        glDisable(GL_DEPTH_TEST);
        glDisable(GL_CULL_FACE);

        glColor4f(1.0f, 1.0f, 1.0f, 1.0f);

        glPushMatrix();
        glTranslatef(manager.window_width/2, manager.window_height/2, 0);
        glDisable(GL_DEPTH_TEST);
        glDisable(GL_CULL_FACE);
        crosshair.bind(delta);
        drawQuad(32, 32);
        crosshair.unbind();
        glEnable(GL_CULL_FACE);
        glEnable(GL_DEPTH_TEST);
        glPopMatrix();

        txtFPS.render(to!dstring(manager.fps));

        glEnable(GL_CULL_FACE);
        glEnable(GL_DEPTH_TEST);
        glEnable(GL_LIGHTING);

        glMatrixMode(GL_PROJECTION);
        glPopMatrix();
        glMatrixMode(GL_MODELVIEW);
    }

    float objDist = 0.0f;

    void shootWithGravityRay(float energy)
    {
        Vector3f forwardVec = camera.absoluteMatrix.forward;
        Vector3f camPos = camera.absoluteMatrix.translation - forwardVec * 2.0f;
        Vector3f objPos = camPos;

            Ray shootRay = Ray(
                camera.absoluteMatrix.translation, 
                camera.absoluteMatrix.translation - forwardVec * 1000.0f);
        if (manager.lmb_pressed)
        {
            float minDistance = float.max;

            if (shootedBody is null)
            {
                foreach(b; world.bodies)
                {
                    if (b !is player.rigidBody)
                    if (b.type == BodyType.Dynamic)
                    {
                        Vector3f ip;
                        // TODO: use geometry bsphere
                        auto sphere = b.geometry.boundingSphere;
                        if (shootRay.intersectSphere(sphere.center, sphere.radius, ip))
                        {
                            float d = distance(camPos, b.position);
                            if (d < minDistance)
                            {
                                shootedBody = b;
                                minDistance = d;

                                objDist = distance(camera.absoluteMatrix.translation, b.position);
                            }
                        }
                    }
                }
            }
/*
            minDistance = float.max;

            if (shootedBody is null)
            {
                world.bvhRoot.traverseByRay(shootRay, (ref Triangle tri)
                {
                    Vector3f rayIntersectionPoint;
                    if (shootRay.intersectTriangle(tri.v[0], tri.v[1], tri.v[2], rayIntersectionPoint))
                    {
                        float d = distance(camPos, rayIntersectionPoint);

                        if (d < minDistance)
                        {
                            minDistance = d;
                            shootedBody = player.rigidBody;
                            objPos = rayIntersectionPoint;
                        }
                    }
                });
            }
*/
        }
        else 
        {
            if (shootedBody)
                shootedBody.disableGravity = false;
            shootedBody = null;
        }

        if (shootedBody)
        {
            shootedBody.disableGravity = true;
            auto b = shootedBody;
            Vector3f fvec = (objPos - b.position).normalized;
            float d = distance(objPos, b.position);
            if (d != 0.0f)
                b.linearVelocity = fvec * d * 5.0f;
        }
    }
}

class SandboxRoom: GameRoom
{
    this(string roomName, GameLogicManager m)
    {
        super(roomName, m);
    }

    override void onLoad()
    {
        glClearColor(0.5f, 0.5f, 0.5f, 1.0f);
        glEnable(GL_LIGHTING);
        glEnable(GL_LIGHT0);

        addObject(new SandboxObject(logic));
    }
}

