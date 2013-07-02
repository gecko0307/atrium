module atrium.dat;

private
{
    import std.stdio;
    import std.path;
    import std.file;
    import dlib.math.vector;
    import dlib.image.color;
    import dlib.image.io.png;
    import dlib.image.image;
    import dlib.geometry.triangle;
    import engine.graphics.material;
    import engine.graphics.texture;
}

enum DatChunkType: ushort
{
    HEADER = 0, 
    END = 1,
    META = 2,
    TRIMESH = 3,
    ENTITY = 4,
    TRIGGER = 5,
    MATERIAL = 6,
    SPAWNPOS = 7,
    COLLECTIBLE = 8,
    ORB = 9
}

struct DatTriangle
{
    int m;
    float[3][3] v;
    float[3][3] n;
    float[2][3] uv1;
    float[2][3] uv2;
}

struct DatTexture
{
    union
    {
        ushort filenameSize;
        ubyte[2] filenameSize_bytes;
    }

    union
    {
        string filename;
        ubyte[] filename_bytes;
    }
    
    union
    {
        ushort blendType;
        ubyte[2] blendType_bytes;
    }
}

struct DatMaterial
{
    union
    {
        int index;
        ubyte[4] index_bytes;
    }
    
    union
    {
        uint shadeless;
        ubyte[4] shadeless_bytes;
    }

    union
    {
        float[3] diffuseColor;
        ubyte[4*3] diffuseColor_bytes;
    }

    union
    {
        float[3] specularColor;
        ubyte[4*3] specularColor_bytes;
    }

    union
    {
        int specularHardness;
        ubyte[4] specularHardness_bytes;
    }

    union
    {
        float danger;
        ubyte[4] danger_bytes;
    }

    union
    {
        ushort walkSoundSize;
        ubyte[2] walkSoundSize_bytes;
    }

    union
    {
        string walkSound;
        ubyte[] walkSound_bytes;
    }

    union
    {
        uint numTextures;
        ubyte[4] numTextures_bytes;
    }

    DatTexture[] textures; 
}

struct DatSpawnpos
{
    float[3] position;
    float[3] rotation;
}

struct DatCollectible
{
    union
    {
        ushort type;
        ubyte[2] type_bytes;
    }
    union
    {
        Vector3f position;
        ubyte[4*3] position_bytes;
    }
}

struct DatOrb
{
    union
    {
        ushort type;
        ubyte[2] type_bytes;
    }
    union
    {
        Vector3f position;
        ubyte[4*3] position_bytes;
    }
}

struct DatChunk
{
    union
    {
        ushort type;
        ubyte[2] type_bytes;
    }

    union
    {
        ushort nameSize;
        ubyte[2] nameSize_bytes;
    }

    union
    {
        uint dataSize;
        ubyte[4] dataSize_bytes;
    }

    union
    {
        string name;
        ubyte[] name_bytes;
    }

    ubyte[] data;
}

class MaterialMetadata
{
    float danger = 0.0f;
    string touchSound = "";
    bool canClimb = true;
}

class Collectible
{
    DatCollectible dat;
    alias dat this;
    bool available = true;

    this(DatCollectible dc)
    {
        dat = dc;
    }
}

class Orb
{
    DatOrb dat;
    alias dat this;

    this(DatOrb dorb)
    {
        dat = dorb;
    }
}

class DatObject
{
    string name = "(Unknown)";

    Material[] materials;
    MaterialMetadata[] materialsMeta;
    Material[int] materialByIndex;
    MaterialMetadata[int] materialMetaByIndex;
    SuperImage[uint] images;
    Texture[string] textures;
    Collectible[] collectibles;
    Orb[] orbs;

    Triangle[] tris;

    Vector3f spawnPosition;
    Vector3f spawnRotation;

    this(string filename)
    {
        spawnPosition = Vector3f(0.0f, 0.0f, 0.0f);
        spawnRotation = Vector3f(0.0f, 0.0f, 0.0f);
        loadFromFile(filename);
    }

    protected void loadFromFile(string filename)
    {
        auto f = new File(filename, "rb");

        DatChunk readChunk()
        {
            DatChunk chunk;
            f.rawRead(chunk.type_bytes);
            f.rawRead(chunk.nameSize_bytes);
            f.rawRead(chunk.dataSize_bytes);

            if (chunk.nameSize > 0)
            {
                chunk.name_bytes = new ubyte[chunk.nameSize];
                f.rawRead(chunk.name_bytes);
            }

            if (chunk.dataSize > 0)
            {
                chunk.data = new ubyte[chunk.dataSize];
                f.rawRead(chunk.data);
            }

            return chunk;
        }
        
        DatChunk[] trimeshChunks;

        DatChunk chunk;
        while (chunk.type != DatChunkType.END && !f.eof)
        {
            chunk = readChunk();

            if (chunk.type == DatChunkType.HEADER)
            {
                // treat header chunk name as object name
                if (chunk.name.length)
                    name = chunk.name;
            }
            else if (chunk.type == DatChunkType.TRIMESH)
            {
                trimeshChunks ~= chunk;
            }
            else if (chunk.type == DatChunkType.SPAWNPOS)
            {
                //writeln(chunk.data.length);
                //writeln(DatSpawnpos.sizeof);
                DatSpawnpos sp = (cast(DatSpawnpos[])chunk.data)[0];
                spawnPosition = Vector3f(sp.position);
                spawnRotation = Vector3f(sp.rotation);
            }
            else if (chunk.type == DatChunkType.COLLECTIBLE)
            {
                //writeln(chunk.data.length);
                //writeln(DatCollectible.sizeof);
                DatCollectible collectible; // = (cast(DatCollectible[])chunk.data)[0];
                size_t offset = 0;
                collectible.type_bytes = chunk.data[offset..offset+2];
                offset += 2;
                collectible.position_bytes = chunk.data[offset..offset+4*3];
                offset += 4*3;
                //collectibles ~= collectible;

                collectibles ~= new Collectible(collectible);
            }
            else if (chunk.type == DatChunkType.ORB)
            {
                //writeln(chunk.data.length);
                //writeln(DatCollectible.sizeof);
                DatOrb orb;
                size_t offset = 0;
                orb.type_bytes = chunk.data[offset..offset+2];
                offset += 2;
                orb.position_bytes = chunk.data[offset..offset+4*3];
                offset += 4*3;
                
                orbs ~= new Orb(orb);
            }
            else if (chunk.type == DatChunkType.MATERIAL)
            {           
                // fill material data
                DatMaterial mat;

                size_t offset = 0;
                mat.index_bytes = chunk.data[offset..offset+4];
                offset += 4;
                mat.shadeless_bytes = chunk.data[offset..offset+4];
                offset += 4;
                mat.diffuseColor_bytes = chunk.data[offset..offset+(4*3)];
                offset += 4 * 3;
                mat.specularColor_bytes = chunk.data[offset..offset+(4*3)];
                offset += 4 * 3;
                mat.specularHardness_bytes = chunk.data[offset..offset+4];
                offset += 4;

                mat.danger_bytes = chunk.data[offset..offset+4];
                offset += 4;
                mat.walkSoundSize_bytes = chunk.data[offset..offset+2];
                offset += 2;
                if (mat.walkSoundSize > 0)
                {
                    mat.walkSound_bytes = new ubyte[mat.walkSoundSize];
                    mat.walkSound_bytes = chunk.data[offset..offset+mat.walkSoundSize];
                    offset += mat.walkSoundSize;
                }

                mat.numTextures_bytes = chunk.data[offset..offset+4];
                offset += 4;

                if (mat.numTextures > 0)
                {
                    mat.textures = new DatTexture[mat.numTextures];

                    foreach(ref tex; mat.textures)
                    {
                        tex.filenameSize_bytes = chunk.data[offset..offset+2];
                        offset += 2;

                        if (tex.filenameSize > 0)
                        {
                            tex.filename_bytes = new ubyte[tex.filenameSize];
                            tex.filename_bytes = chunk.data[offset..offset+tex.filenameSize];
                            offset += tex.filenameSize;
                        }

                        tex.blendType_bytes = chunk.data[offset..offset+2];
                        offset += 2;
                        
                        //writeln(tex.blendType);
                    }
                }
            
                // prevent duplicating
                if (!(mat.index in materialByIndex))
                {
                    Material matObj = new Material();
                    matObj.shadeless = cast(bool)mat.shadeless;
                    //matObj.diffuseColor = ColorRGBAf(Vector3f(mat.diffuseColor));
                    //matObj.specularColor = ColorRGBAf(Vector3f(mat.specularColor));
                    matObj.shininess = mat.specularHardness;

                    MaterialMetadata matMetaObj = new MaterialMetadata();
                    matMetaObj.danger = mat.danger;
                    matMetaObj.touchSound = mat.walkSound;
                    if (matMetaObj.danger == 0.0f)
                        matMetaObj.canClimb = false;

                    foreach(texi, tex; mat.textures)
                    {
                        //writeln(tex.filename);
                        string directoryPath = dirName(filename);
                        //writeln(directoryPath);
                        string texImgPath = buildNormalizedPath(directoryPath, tex.filename);
                        //writeln(texImgPath);

                        if (exists(texImgPath))
                        {
                            // for now, only PNG textures are supported by the engine
                            if (extension(texImgPath) == ".png" ||
                                extension(texImgPath) == ".PNG")
                            {
                                if (!(texImgPath in textures))
                                {
                                    auto texImg = loadPNG(texImgPath);
                                    Texture texObj = new Texture(texImg);
                                    textures[texImgPath] = texObj;
                                    matObj.textures[texi] = texObj;
                                    images[texObj.tex] = texImg;
                                }
                                else
                                {
                                    matObj.textures[texi] = textures[texImgPath];
                                }

                                matObj.texBlendMode[texi] = tex.blendType;
                            }
                            else
                                writefln("Warning: unsupported file type (trying to load \'%s\')", texImgPath);
                        }
                    }

                    if (matObj.textures[0] is null &&
                        matObj.textures[1] !is null)
                    {
                        matObj.textures[0] = matObj.textures[1];
                        matObj.texBlendMode[0] = TextureCombinerMode.Blend;
                        matObj.shadeless = true;
                    }
                    else if (matObj.textures[0] !is null)
                        matObj.shadeless = true;
                    
                    materials ~= matObj;
                    materialsMeta ~= matMetaObj;

                    materialByIndex[mat.index] = matObj;
                    materialMetaByIndex[mat.index] = matMetaObj;
                }
            
                // TODO: add support to select material by name
            }
        }

        f.close();

        int totalTris = 0;

        // calculate total triangle count
        foreach(ref trimesh; trimeshChunks)
        {
            // be sure data is consistent
            assert(!(trimesh.data.length % DatTriangle.sizeof));

            // adjust triangle count
            totalTris += trimesh.data.length / DatTriangle.sizeof;
        }

        tris = new Triangle[totalTris];
     
        uint offset = 0;
        foreach(ref trimesh; trimeshChunks)
        {
            // interpret data as an array of triangles
            DatTriangle[] mtris = cast(DatTriangle[])trimesh.data;

            foreach(i, mtri; mtris)
            {
                Triangle* tri = &tris[offset];

                tri.v[0] = Vector3f(mtri.v[0]);
                tri.v[1] = Vector3f(mtri.v[1]);
                tri.v[2] = Vector3f(mtri.v[2]);

                tri.n[0] = Vector3f(mtri.n[0]);
                tri.n[1] = Vector3f(mtri.n[1]);
                tri.n[2] = Vector3f(mtri.n[2]);

                tri.t1[0] = Vector2f(mtri.uv1[0]);
                tri.t1[1] = Vector2f(mtri.uv1[1]);
                tri.t1[2] = Vector2f(mtri.uv1[2]);
                
                tri.t2[0] = Vector2f(mtri.uv2[0]);
                tri.t2[1] = Vector2f(mtri.uv2[1]);
                tri.t2[2] = Vector2f(mtri.uv2[2]);
                
                tri.materialIndex = mtri.m;

                tri.normal = normal(tri.v[0], tri.v[1], tri.v[2]);
                
                tri.barycenter = (tri.v[0] + tri.v[1] + tri.v[2]) / 3;

                tri.d = (tri.v[0].x * tri.normal.x + 
                         tri.v[0].y * tri.normal.y + 
                         tri.v[0].z * tri.normal.z);

                tri.edges[0] = tri.v[1] - tri.v[0];
                tri.edges[1] = tri.v[2] - tri.v[1];
                tri.edges[2] = tri.v[0] - tri.v[2];

                offset++;
            }
        }        
    }
}


