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

module dlib.image.io.jpeg;

import std.stdio;
import std.algorithm;
import std.string;
import std.traits;

import dlib.core.memory;
import dlib.core.stream;
import dlib.core.compound;
import dlib.container.array;
import dlib.filesystem.local;
import dlib.image.color;
import dlib.image.image;
import dlib.image.io.idct;

import dlib.core.bitio;
import dlib.coding.huffman;

/*
 * Simple JPEG decoder
 *
 * Limitations:
 *  - Doesn't support progressive JPEG
 *  - Doesn't perform chroma interpolation
 *  - Doesn't read EXIF metadata
 */

// Uncomment this to see debug messages
//version = JPEGDebug;

T readNumeric(T) (InputStream istrm, Endian endian = Endian.Little)
if (is(T == ubyte))
{
    ubyte b;
    istrm.readBytes(&b, 1);
    return b;
}

T readNumeric(T) (InputStream istrm, Endian endian = Endian.Little)
if (is(T == ushort))
{
    union U16
    { 
        ubyte[2] asBytes;
        ushort asUshort;
    }
    U16 u16;
    istrm.readBytes(u16.asBytes.ptr, 2);
    version(LittleEndian)
    {
        if (endian == Endian.Big)
            return u16.asUshort.swapEndian16;
        else
            return u16.asUshort;
    }
    else
    {
        if (endian == Endian.Little)
            return u16.asUshort.swapEndian16;
        else
            return u16.asUshort;
    }
}

char[size] readChars(size_t size) (InputStream istrm)
{
    char[size] chars;
    istrm.readBytes(chars.ptr, size);
    return chars;
}

/*
 * JPEG-related Huffman coding
 */

struct HuffmanCode
{
    ushort bits;
    ushort length;
    
    auto bitString()
    {
        return .bitString(bits, length);
    }
}

struct HuffmanTableEntry
{
    HuffmanCode code;
    ubyte value;
}

DynamicArray!char bitString(T)(T n, uint len = 1) if (isIntegral!T)
{
    DynamicArray!char arr;

    const int size = T.sizeof * 8;
    
    bool s = 0;
    for (int a = 0; a < size; a++)
    {
        bool bit = n >> (size - 1);
        if (bit)
            s = 1;
        if (s)
        {
            arr.append(bit + '0');
        }
        n <<= 1;
    }
    
    while (arr.length < len)
        arr.appendLeft('0');
        
    return arr;
}

HuffmanTreeNode* emptyNode()
{
    return New!HuffmanTreeNode(null, null, cast(ubyte)0, 0, false);
}

HuffmanTreeNode* treeFromTable(DynamicArray!(HuffmanTableEntry) table)
{
    HuffmanTreeNode* root = emptyNode();

    foreach(i, v; table.data)
        treeAddCode(root, v.code, v.value);

    return root;
}

void treeAddCode(HuffmanTreeNode* root, HuffmanCode code, ubyte value)
{
    HuffmanTreeNode* node = root;
    auto bs = code.bitString;
    foreach(bit; bs.data)
    {
        if (bit == '0')
        {
            if (node.left is null)
            {
                node.left = emptyNode();
                node.left.parent = node;
            }

            node = node.left;
        }
        else if (bit == '1')
        {
            if (node.right is null)
            {
                node.right = emptyNode();
                node.right.parent = node;
            }

            node = node.right;
        }
    }
    assert (node !is null);
    node.ch = value;
    bs.free();
}

/*
 * JPEG-related data types
 */

enum JPEGMarkerType
{
    Unknown,
    SOI,
    SOF0,
    SOF1,
    SOF2,
    DHT,
    DQT,
    DRI,
    SOS,
    RSTn,
    APP0,
    APPn,
    COM,
    EOI
}

struct JPEGImage
{
    struct JFIF
    {
        ubyte versionMajor;
        ubyte versionMinor;
        ubyte units;
        ushort xDensity;
        ushort yDensity;
        ubyte thumbnailWidth;
        ubyte thumbnailHeight;
        ubyte[] thumbnail;

        void free()
        {
            if (thumbnail.length)
                Delete(thumbnail);
        }
    }

    struct DQT
    {
        ubyte precision;
        ubyte tableId;
        ubyte[] table;

        void free()
        {
            if (table.length)
                Delete(table);
        }
    }

    struct SOF0Component
    {
        ubyte hSubsampling;
        ubyte vSubsampling;
        ubyte dqtTableId;
    }

    struct SOF0
    {
        ubyte precision;
        ushort height;
        ushort width;
        ubyte componentsNum;
        SOF0Component[] components;

        void free()
        {
            if (components.length)
                Delete(components);
        }
    }

    struct DHT
    {
        ubyte clas;
        ubyte tableId;
        DynamicArray!HuffmanTableEntry huffmanTable;
        HuffmanTreeNode* huffmanTree;

        void free()
        {
            huffmanTree.free();
            Delete(huffmanTree);
            huffmanTable.free();
        }
    }

    struct SOSComponent
    {
        ubyte tableIdDC;
        ubyte tableIdAC;
    }

    struct SOS
    {
        ubyte componentsNum;
        SOSComponent[] components;
        ubyte spectralSelectionStart;
        ubyte spectralSelectionEnd;
        ubyte successiveApproximationBitHigh;
        ubyte successiveApproximationBitLow;

        void free()
        {
            if (components.length)
                Delete(components);
        }
    }

    JFIF jfif;
    DQT[] dqt;
    SOF0 sof0;
    DHT[] dht;
    SOS sos;

    DQT* addDQT()
    {
        if (dqt.length > 0)
            reallocateArray(dqt, dqt.length+1);
        else
            dqt = New!(DQT[])(1);
        return &dqt[$-1];
    }

    DHT* addDHT()
    {
        if (dht.length > 0)
            reallocateArray(dht, dht.length+1);
        else
            dht = New!(DHT[])(1);
        return &dht[$-1];
    }

    void free()
    {
        jfif.free();
        foreach(ref t; dqt) t.free();
        if (dqt.length)
            Delete(dqt);
        sof0.free();
        foreach(ref t; dht) t.free();
        if (dht.length)
            Delete(dht);
        sos.free();
    }

    DQT* getQuantizationTable(ubyte id)
    {
        foreach(ref t; dqt)
            if (t.tableId == id)
                return &t;
        return null;
    }
    
    DHT* getHuffmanTable(ubyte clas, ubyte id)
    {
        foreach(ref t; dht)
            if (t.clas == clas &&
                t.tableId == id)
                return &t;
        return null;
    }
}

/*
 * Load JPEG from file using local FileSystem.
 * Causes GC allocation
 */
SuperImage loadJPEG(string filename)
{
    InputStream input = openForInput(filename);
    auto img = loadJPEG(input);    input.close();
    return img;
}

/*
 * Load JPEG from stream using default image factory.
 * Causes GC allocation
 */
SuperImage loadJPEG(InputStream istrm)
{
    Compound!(SuperImage, string) res = 
        loadJPEG(istrm, defaultImageFactory);
    if (res[0] is null)
        throw new Exception(res[1]);
    else
        return res[0];
}

/*
 * Load JPEG from stream using specified image factory.
 * GC-free
 */
Compound!(SuperImage, string) loadJPEG(
    InputStream istrm, 
    SuperImageFactory imgFac)
{
    JPEGImage jpg;
    SuperImage img = null;
    
    while (istrm.readable)
    {
        JPEGMarkerType mt;
        auto res = readMarker(&jpg, istrm, &mt);
        if (res[0])
        {
            // TODO: add progressive JPEG support
            if (mt == JPEGMarkerType.SOF2)
            {
                jpg.free();
                return compound(img, "loadJPEG error: progressive JPEG is not supported");
            }
            else if (mt == JPEGMarkerType.SOS)
                break;
        }
        else
        {
            jpg.free();
            return compound(img, res[1]);
        }
    }
    auto res = decodeScanData(&jpg, istrm, imgFac);
    jpg.free();
    return res;
}

/*
 *  Decode marker from JPEG stream
 */
Compound!(bool, string) readMarker(
    JPEGImage* jpg,
    InputStream istrm,
    JPEGMarkerType* mt)
{
    ushort magic = istrm.readNumeric!ushort(Endian.Big);
    
    switch (magic)
    {
        case 0xFFD8:
            *mt = JPEGMarkerType.SOI;
            version(JPEGDebug) writeln("SOI");
            break;
            
        case 0xFFE0:
            *mt = JPEGMarkerType.APP0;
            return readJFIF(jpg, istrm);

        case 0xFFE1:
            *mt = JPEGMarkerType.APPn;
            return readAPPn(jpg, istrm, 1);
            
        case 0xFFE2:
            *mt = JPEGMarkerType.APPn;
            return readAPPn(jpg, istrm, 2);
            
        case 0xFFE3:
            *mt = JPEGMarkerType.APPn;
            return readAPPn(jpg, istrm, 3);
            
        case 0xFFE4:
            *mt = JPEGMarkerType.APPn;
            return readAPPn(jpg, istrm, 4);
            
        case 0xFFE5:
            *mt = JPEGMarkerType.APPn;
            return readAPPn(jpg, istrm, 5);
            
        case 0xFFE6:
            *mt = JPEGMarkerType.APPn;
            return readAPPn(jpg, istrm, 6);
            
        case 0xFFE7:
            *mt = JPEGMarkerType.APPn;
            return readAPPn(jpg, istrm, 7);
            
        case 0xFFE8:
            *mt = JPEGMarkerType.APPn;
            return readAPPn(jpg, istrm, 8);
            
         case 0xFFE9:
            *mt = JPEGMarkerType.APPn;
            return readAPPn(jpg, istrm, 9);
            
         case 0xFFEA:
            *mt = JPEGMarkerType.APPn;
            return readAPPn(jpg, istrm, 10);
            
         case 0xFFEB:
            *mt = JPEGMarkerType.APPn;
            return readAPPn(jpg, istrm, 11);
            
         case 0xFFEC:
            *mt = JPEGMarkerType.APPn;
            return readAPPn(jpg, istrm, 12);
            
         case 0xFFED:
            *mt = JPEGMarkerType.APPn;
            return readAPPn(jpg, istrm, 13);
            
         case 0xFFEE:
            *mt = JPEGMarkerType.APPn;
            return readAPPn(jpg, istrm, 14);
            
         case 0xFFEF:
            *mt = JPEGMarkerType.APPn;
            return readAPPn(jpg, istrm, 15);
            
        case 0xFFDB:
            *mt = JPEGMarkerType.DQT;
            return readDQT(jpg, istrm);
            
        case 0xFFC0:
            *mt = JPEGMarkerType.SOF0;
            return readSOF0(jpg, istrm);

        case 0xFFC2:
            *mt = JPEGMarkerType.SOF2;            break;
            
        case 0xFFC4:
            *mt = JPEGMarkerType.DHT;
            return readDHT(jpg, istrm);
            
        case 0xFFDA:
            *mt = JPEGMarkerType.SOS;
            return readSOS(jpg, istrm);

        case 0xFFFE:
            *mt = JPEGMarkerType.COM;
            return readCOM(jpg, istrm);
            
        default:
            *mt = JPEGMarkerType.Unknown;
            break;
    }
    
    return compound(true, "");
}

Compound!(bool, string) readJFIF(JPEGImage* jpg, InputStream istrm)
{
    ushort jfif_length = istrm.readNumeric!ushort(Endian.Big);

    char[5] jfif_id = istrm.readChars!5;
    if (jfif_id != "JFIF\0")
        return compound(false, "loadJPEG error: illegal JFIF header");

    jpg.jfif.versionMajor = istrm.readNumeric!ubyte;
    jpg.jfif.versionMinor = istrm.readNumeric!ubyte;
    jpg.jfif.units = istrm.readNumeric!ubyte;
    jpg.jfif.xDensity = istrm.readNumeric!ushort(Endian.Big);
    jpg.jfif.yDensity = istrm.readNumeric!ushort(Endian.Big);
    jpg.jfif.thumbnailWidth = istrm.readNumeric!ubyte;
    jpg.jfif.thumbnailHeight = istrm.readNumeric!ubyte;
    
    uint jfif_thumb_length = jpg.jfif.thumbnailWidth * jpg.jfif.thumbnailHeight * 3;
    if (jfif_thumb_length > 0)
    {
        jpg.jfif.thumbnail = New!(ubyte[])(jfif_thumb_length);
        istrm.readBytes(jpg.jfif.thumbnail.ptr, jfif_thumb_length);
    }

    version(JPEGDebug)
    {
        writefln("APP0/JFIF length: %s", jfif_length);
        writefln("APP0/JFIF identifier: %s", jfif_id);
        writefln("APP0/JFIF version major: %s", jpg.jfif.versionMajor);
        writefln("APP0/JFIF version minor: %s", jpg.jfif.versionMinor);
        writefln("APP0/JFIF units: %s", jpg.jfif.units);
        writefln("APP0/JFIF xdensity: %s", jpg.jfif.xDensity);
        writefln("APP0/JFIF ydensity: %s", jpg.jfif.yDensity);
        writefln("APP0/JFIF xthumbnail: %s", jpg.jfif.thumbnailWidth);
        writefln("APP0/JFIF ythumbnail: %s", jpg.jfif.thumbnailHeight);
    }

    return compound(true, "");
}

/*
 * APP1 - EXIF, XMP, ExtendedXMP, QVCI, FLIR
 * APP2 - ICC, FPXR, MPF, PreviewImage
 * APP3 - Kodak Meta, Stim, PreviewImage
 * APP4 - Scalado, FPXR, PreviewImage
 * APP5 - RMETA, PreviewImage
 * APP6 - EPPIM, NITF, HP TDHD
 * APP7 - Pentax, Qualcomm
 * APP8 - SPIFF
 * APP9 - MediaJukebox
 * APP10 - PhotoStudio comment
 * APP11 - JPEG-HDR
 * APP12 - PictureInfo, Ducky
 * APP13 - Photoshop, Adobe CM
 * APP14 - Adobe
 * APP15 - GraphicConverter
 */
Compound!(bool, string) readAPPn(JPEGImage* jpg, InputStream istrm, uint n)
{
    ushort app_length = istrm.readNumeric!ushort(Endian.Big);
    ubyte[] app = New!(ubyte[])(app_length-2);
    istrm.readBytes(app.ptr, app_length-2);

    // TODO: interpret APP data (EXIF etc.) and save it somewhere.
    // Maybe add a generic ImageInfo object for this?
    Delete(app);

    version(JPEGDebug)
    {
        writefln("APP%s length: %s", n, app_length);
    }

    return compound(true, "");
}

Compound!(bool, string) readCOM(JPEGImage* jpg, InputStream istrm)
{
    ushort com_length = istrm.readNumeric!ushort(Endian.Big);
    ubyte[] com = New!(ubyte[])(com_length-2);
    istrm.readBytes(com.ptr, com_length-2);

    version(JPEGDebug)
    {
        writefln("COM string: \"%s\"", cast(string)com);
        writefln("COM length: %s", com_length);
    }    

    // TODO: save COM data somewhere.
    // Maybe add a generic ImageInfo object for this?
    Delete(com);

    return compound(true, "");
}

Compound!(bool, string) readDQT(JPEGImage* jpg, InputStream istrm)
{   
    ushort dqt_length = istrm.readNumeric!ushort(Endian.Big);
    version(JPEGDebug)
    {
        writefln("DQT length: %s", dqt_length);
    }

    dqt_length -= 2;

    while(dqt_length)
    {
        JPEGImage.DQT* dqt = jpg.addDQT();

        ubyte bite = istrm.readNumeric!ubyte;
        dqt.precision = bite.hiNibble;
        dqt.tableId = bite.loNibble;

        dqt_length--;

        if (dqt.precision == 0)
        {
            dqt.table = New!(ubyte[])(64);
            dqt_length -= 64;
        }
        else if (dqt.precision == 1)
        {
            dqt.table = New!(ubyte[])(128);
            dqt_length -= 128;
        }

        istrm.readBytes(dqt.table.ptr, dqt.table.length);

        version(JPEGDebug)
        {
            writefln("DQT precision: %s", dqt.precision);
            writefln("DQT table id: %s", dqt.tableId);
            writefln("DQT table: %s", dqt.table);
        }
    }

    return compound(true, "");
}

Compound!(bool, string) readSOF0(JPEGImage* jpg, InputStream istrm)
{   
    ushort sof0_length = istrm.readNumeric!ushort(Endian.Big);
    jpg.sof0.precision = istrm.readNumeric!ubyte;
    jpg.sof0.height = istrm.readNumeric!ushort(Endian.Big);
    jpg.sof0.width = istrm.readNumeric!ushort(Endian.Big);
    jpg.sof0.componentsNum = istrm.readNumeric!ubyte;
    
    version(JPEGDebug)
    {
        writefln("SOF0 length: %s", sof0_length);
        writefln("SOF0 precision: %s", jpg.sof0.precision);
        writefln("SOF0 height: %s", jpg.sof0.height);
        writefln("SOF0 width: %s", jpg.sof0.width);
        writefln("SOF0 components: %s", jpg.sof0.componentsNum);
    }
    
    jpg.sof0.components = New!(JPEGImage.SOF0Component[])(jpg.sof0.componentsNum);
    
    foreach(ref c; jpg.sof0.components)
    {
        ubyte c_id = istrm.readNumeric!ubyte;
        ubyte bite = istrm.readNumeric!ubyte;
        c.hSubsampling = bite.hiNibble;
        c.vSubsampling = bite.loNibble;
        c.dqtTableId = istrm.readNumeric!ubyte;
        version(JPEGDebug)
        {
            writefln("SOF0 component id: %s", c_id);
            writefln("SOF0 component %s hsubsampling: %s", c_id, c.hSubsampling);
            writefln("SOF0 component %s vsubsampling: %s", c_id, c.vSubsampling);
            writefln("SOF0 component %s table id: %s", c_id, c.dqtTableId);
        }
    }

    return compound(true, "");
}

Compound!(bool, string) readDHT(JPEGImage* jpg, InputStream istrm)
{    
    ushort dht_length = istrm.readNumeric!ushort(Endian.Big);  
    version(JPEGDebug)
    {
        writefln("DHT length: %s", dht_length);
    }
  
    dht_length -= 2;

    while(dht_length > 0)
    {    
        JPEGImage.DHT* dht = jpg.addDHT();
    
        ubyte bite = istrm.readNumeric!ubyte;
        dht_length--;
        dht.clas = bite.hiNibble;
        dht.tableId = bite.loNibble;

        ubyte[16] dht_code_lengths;
        istrm.readBytes(dht_code_lengths.ptr, 16);
        dht_length -= 16;

        version(JPEGDebug)
        {
            writefln("DHT class: %s (%s)",
                dht.clas,
                dht.clas? "AC":"DC");
            writefln("DHT tableId: %s", dht.tableId);
            writefln("DHT Huffman code lengths: %s", dht_code_lengths);
        }
    
        // Read Huffman table   
        int totalCodes = reduce!("a + b")(0, dht_code_lengths);
        int storedCodes = 0;
        ubyte treeLevel = 0;
        ushort bits = 0;
    
        while (storedCodes != totalCodes)
        {
            while (treeLevel < 15 && 
                dht_code_lengths[treeLevel] == 0)
            {
                treeLevel++;
                bits *= 2;
            }

            if (treeLevel < 16)
            {
                uint bitsNum = treeLevel + 1;
                HuffmanCode code = HuffmanCode(bits, cast(ushort)bitsNum);

                auto entry = HuffmanTableEntry(code, istrm.readNumeric!ubyte);
                dht.huffmanTable.append(entry);

                dht_length--;
            
                storedCodes++;
                bits++;
                dht_code_lengths[treeLevel]--;
            }
        }

        dht.huffmanTree = treeFromTable(dht.huffmanTable);
    }

    return compound(true, "");
}

Compound!(bool, string) readSOS(JPEGImage* jpg, InputStream istrm)
{   
    ushort sos_length = istrm.readNumeric!ushort(Endian.Big);
    jpg.sos.componentsNum = istrm.readNumeric!ubyte;

    version(JPEGDebug)
    {
        writefln("SOS length: %s", sos_length);
        writefln("SOS components: %s", jpg.sos.componentsNum);
    }
    
    jpg.sos.components = New!(JPEGImage.SOSComponent[])(jpg.sos.componentsNum);
    
    foreach(ref c; jpg.sos.components)
    {
        ubyte c_id = istrm.readNumeric!ubyte;
        ubyte bite = istrm.readNumeric!ubyte;
        c.tableIdDC = bite.hiNibble;
        c.tableIdAC = bite.loNibble;
        version(JPEGDebug)
        {
            writefln("SOS component id: %s", c_id);
            writefln("SOS component %s DC table id: %s", c_id, c.tableIdDC);
            writefln("SOS component %s AC table id: %s", c_id, c.tableIdAC);
        }
    }

    jpg.sos.spectralSelectionStart = istrm.readNumeric!ubyte;
    jpg.sos.spectralSelectionEnd = istrm.readNumeric!ubyte;
    ubyte bite = istrm.readNumeric!ubyte;
    jpg.sos.successiveApproximationBitHigh = bite.hiNibble;
    jpg.sos.successiveApproximationBitLow = bite.loNibble;
    
    version(JPEGDebug)
    {
        writefln("SOS spectral selection start: %s", jpg.sos.spectralSelectionStart);
        writefln("SOS spectral selection end: %s", jpg.sos.spectralSelectionEnd);
        writefln("SOS successive approximation bit: %s", jpg.sos.successiveApproximationBitHigh);
        writefln("SOS successive approximation bit low: %s", jpg.sos.successiveApproximationBitLow);
    }

    return compound(true, "");
}

struct ScanBitStream
{
    InputStream istrm;

    bool endMarkerFound = false;
    uint bytesRead = 0;
    ubyte prevByte = 0x00;
    ubyte curByte = 0x00;

    ubyte readNextByte()
    {
        ubyte b = istrm.readNumeric!ubyte;
        bytesRead++;
        endMarkerFound = (prevByte == 0xFF && b == 0xD9);
        assert(!endMarkerFound);
        if (!endMarkerFound)
        {
            prevByte = b;
            curByte = b;
            return b;
        }
        else
        {
            curByte = 0;
        }
        return curByte;
    }

    bool readable()
    {
        return !istrm.readable || endMarkerFound;
    }

    uint bitPos = 0;

    // Huffman decode a byte
    Compound!(bool, string) decodeByte(HuffmanTreeNode* node, ubyte* result)
    {
        while(!node.isLeaf)
        {
            ubyte b = curByte;
        
            bool bit = getBit(b, 7-bitPos);
            bitPos++;
            if (bitPos == 8)
            {
                bitPos = 0;
                readNextByte();
                
                if (b == 0xFF)
                {
                    b = curByte; 
                    if (b == 0x00)
                    {
                        readNextByte();
                    }
                }
            }
            
            if (bit) 
                node = node.right;
            else 
                node = node.left;

            if (node is null)
                return compound(false, "loadJPEG error: no Huffman code found");
        }

        *result = node.ch;
        return compound(true, "");
    }

    // Read len bits from stream to buffer
    uint readBits(ubyte len)
    {
        uint buffer = 0;
        uint i = 0;
        uint by = 0;
        uint bi = 0;

        while (i < len)
        {
            ubyte b = curByte;
        
            bool bit = getBit(b, 7-bitPos);
            buffer = setBit(buffer, (by * 8 + bi), bit);

            bi++;
            if (bi == 8)
            {
                bi = 0;
                by++;
            }

            i++;

            bitPos++;
            if (bitPos == 8)
            {
                bitPos = 0;
                readNextByte();

                if (b == 0xFF)
                {
                    b = curByte;
                    if (b == 0x00)
                        readNextByte();
                }
            }
        }

        return buffer;
    }
}

/*
 *  Decodes compressed data and creates RGB image from it
 */
Compound!(SuperImage, string) decodeScanData(
    JPEGImage* jpg,
    InputStream istrm,
    SuperImageFactory imgFac)
{
    SuperImage img = imgFac.createImage(jpg.sof0.width, jpg.sof0.height, 3, 8);

    MCU mcu;
    foreach(ci, ref c; jpg.sof0.components)
    {
        if (ci == 0)
            mcu.createYBlocks(c.hSubsampling, c.vSubsampling);
        else if (ci == 1)
            mcu.createCbBlocks(c.hSubsampling, c.vSubsampling);
        else if (ci == 2)
            mcu.createCrBlocks(c.hSubsampling, c.vSubsampling);
    }

    Compound!(SuperImage, string) error(string errorMsg)
    {
        mcu.free();
        if (img)
        {
            img.free();
            img = null;
        }
        return compound(img, errorMsg);
    }

    // Decode DCT coefficient from bit buffer
    int decodeCoef(uint buffer, ubyte numBits)
    {
        bool positive = getBit(buffer, 0);
        
        int value = 0;
        foreach(j; 0..numBits)
        {
            bool bit = getBit(buffer, numBits-1-j);
            value = setBit(value, j, bit);
        }
        
        if (positive)
            return value;
        else
            return value - 2^^numBits + 1;
    }

    static const ubyte[64] dezigzag =
    [
         0,  1,  8, 16,  9,  2,  3, 10,
        17, 24, 32, 25, 18, 11,  4,  5,
        12, 19, 26, 33, 40, 48, 41, 34,
        27, 20, 13,  6,  7, 14, 21, 28,
        35, 42, 49, 56, 57, 50, 43, 36,
        29, 22, 15, 23, 30, 37, 44, 51,
        58, 59, 52, 45, 38, 31, 39, 46,
        53, 60, 61, 54, 47, 55, 62, 63
    ];

    if (jpg.sos.componentsNum != 3)
    {
        return error(format(
                "loadJPEG error: unsupported number of components: %s",
                jpg.sos.componentsNum));
    }

    // Store previous DC coefficients
    int[3] dcCoefPrev;

    if (jpg.dqt.length == 0)
        return error("loadJPEG error: no DQTs found");

    ScanBitStream sbs;
    sbs.endMarkerFound = false;
    sbs.bytesRead = 0;
    sbs.prevByte = 0x00;
    sbs.curByte = 0x00;
    sbs.istrm = istrm;
    sbs.readNextByte();

    uint numMCUsH = jpg.sof0.width / mcu.width + ((jpg.sof0.width % mcu.width) > 0);
    uint numMCUsV = jpg.sof0.height / mcu.height + ((jpg.sof0.height % mcu.height) > 0);

    // Read MCUs
    foreach(mcuY; 0..numMCUsV)
    foreach(mcuX; 0..numMCUsH)
    {
        // Read MCU for each channel
        foreach(ci, ref c; jpg.sos.components)
        {
            auto tableDC = jpg.getHuffmanTable(0, c.tableIdDC);
            auto tableAC = jpg.getHuffmanTable(1, c.tableIdAC);

            if (tableDC is null)
                return error("loadJPEG error: illegal DC table index in MCU component");
            if (tableAC is null)
                return error("loadJPEG error: illegal AC table index in MCU component");

            auto component = jpg.sof0.components[ci];
            auto hblocks = component.hSubsampling;
            auto vblocks = component.vSubsampling;
            auto dqtTableId = component.dqtTableId;
            if (dqtTableId >= jpg.dqt.length)
                return error("loadJPEG error: illegal DQT table index in MCU component");

            // Read 8x8 blocks
            foreach(by; 0..vblocks)
            foreach(bx; 0..hblocks)
            {
                int[8*8] block;

                // Read DC coefficient
                ubyte dcDiffLen;
                auto res = sbs.decodeByte(tableDC.huffmanTree, &dcDiffLen);
                if (!res[0]) return error(res[1]); 

                if (dcDiffLen > 0)
                {
                    uint dcBuffer = sbs.readBits(dcDiffLen);
                    dcCoefPrev[ci] += decodeCoef(dcBuffer, dcDiffLen);
                }

                block[0] = dcCoefPrev[ci];

                // Read AC coefficients
                {
                    uint i = 1;
                    bool eob = false;
                    while (!eob && i < 64)
                    {
                        ubyte code;
                        res = sbs.decodeByte(tableAC.huffmanTree, &code);
                        if (!res[0]) return error(res[1]);

                        if (code == 0x00) // EOB, all next values are zero
                            eob = true;
                        else if (code == 0xF0) // ZRL, next 16 values are zero
                        {
                            foreach(j; 0..16)
                            if (i < 64)
                            {
                                block[i] = 0;
                                i++;
                            }
                        }
                        else
                        {
                            ubyte hi = hiNibble(code);
                            ubyte lo = loNibble(code);

                            uint zeroes = hi;
                            foreach(j; 0..zeroes)
                            if (i < 64)
                            {
                                block[i] = 0;
                                i++;
                            }

                            int acCoef = 0;     
                            if (lo > 0)
                            {
                                uint acBuffer = sbs.readBits(lo);
                                acCoef = decodeCoef(acBuffer, lo);
                            }

                            if (i < 64)
                                block[i] = acCoef;

                            i++;
                        }
                    }
                }

                // Multiply block by quantization matrix
                foreach(i, ref v; block)
                    v *= jpg.dqt[dqtTableId].table[i];

                // Convert matrix from zig-zag order to normal order
                int[8*8] dctMatrix;

                foreach(i, v; block)
                    dctMatrix[dezigzag[i]] = v;

                idct64(dctMatrix.ptr);

                // Copy the matrix into corresponding channel
                int* outMatrixPtr;
                if (ci == 0)
                    outMatrixPtr = mcu.yBlocks[by * hblocks + bx].ptr;
                else if (ci == 1)
                    outMatrixPtr = mcu.cbBlocks[by * hblocks + bx].ptr;
                else if (ci == 2)
                    outMatrixPtr = mcu.crBlocks[by * hblocks + bx].ptr;
                else
                    return error("loadJPEG error: illegal component index");

                for(uint i = 0; i < 64; i++)
                    outMatrixPtr[i] = dctMatrix[i];
            }
        }

        // Convert MCU from YCbCr to RGB
        foreach(y; 0..mcu.height) // Pixel coordinates in MCU
        foreach(x; 0..mcu.width)
        {
            Color4f col = mcu.getPixel(x, y);

            // Pixel coordinates in image
            uint ix = mcuX * mcu.width + x;
            uint iy = mcuY * mcu.height + y;

            if (ix < img.width && iy < img.height)
                img[ix, iy] = col;
        }
    }

    version(JPEGDebug)
    {
        writefln("Bytes read: %s", sbs.bytesRead);
    }

    mcu.free();

    return compound(img, "");
}

/*
 * MCU struct keeps a storage for one Minimal Code Unit
 * and provides a generalized interface for decoding
 * images with different subsampling modes.
 * Decoder should read 8x8 blocks one by one for each channel
 * and fill corresponding arrays in MCU.
 */
struct MCU
{
    uint width;
    uint height;

    alias int[8*8] Block;
    Block[] yBlocks;
    Block[] cbBlocks;
    Block[] crBlocks;

    uint ySamplesH, ySamplesV;
    uint cbSamplesH, cbSamplesV;
    uint crSamplesH, crSamplesV;

    uint yWidth, yHeight;
    uint cbWidth, cbHeight;
    uint crWidth, crHeight;

    void createYBlocks(uint hsubsampling, uint vsubsampling)
    {
        yBlocks = New!(Block[])(hsubsampling * vsubsampling);

        width = hsubsampling * 8;
        height = vsubsampling * 8;

        ySamplesH = hsubsampling;
        ySamplesV = vsubsampling;

        yWidth = width / ySamplesH;
        yHeight = height / ySamplesV;
    }

    void createCbBlocks(uint hsubsampling, uint vsubsampling)
    {
        cbBlocks = New!(Block[])(hsubsampling * vsubsampling);

        cbSamplesH = hsubsampling;
        cbSamplesV = vsubsampling;

        cbWidth = width / cbSamplesH;
        cbHeight = height / cbSamplesV;
    }

    void createCrBlocks(uint hsubsampling, uint vsubsampling)
    {
        crBlocks = New!(Block[])(hsubsampling * vsubsampling);

        crSamplesH = hsubsampling;
        crSamplesV = vsubsampling;

        crWidth = width / crSamplesH;
        crHeight = height / crSamplesV;
    }

    void free()
    {
        if (yBlocks.length) Delete(yBlocks);
        if (cbBlocks.length) Delete(cbBlocks);
        if (crBlocks.length) Delete(crBlocks);
    }

    Color4f getPixel(uint x, uint y) // coordinates relative to upper-left MCU corner 
    {
        // Y block coordinates
        uint ybx = x / yWidth;
        uint yby = y / yHeight;
        uint ybi = yby * ySamplesH + ybx;

        // Pixel coordinates in Y block
        uint ybpx = x - ybx * yWidth;
        uint ybpy = y - yby * yHeight;

        // Cb block coordinates
        uint cbx = x / cbWidth;
        uint cby = y / cbHeight;
        uint cbi = cby * cbSamplesH + cbx;

        // Pixel coordinates in Cb block
        uint cbpx = (x - cbx * cbWidth)  / ySamplesH;
        uint cbpy = (y - cby * cbHeight) / ySamplesV;

        // Cr block coordinates
        uint crx = x / crWidth;
        uint cry = y / crHeight;
        uint cri = cry * crSamplesH + crx;

        // Pixel coordinates in Cr block
        uint crpx = (x - crx * crWidth)  / ySamplesH;
        uint crpy = (y - cry * crHeight) / ySamplesV;

        // Get color components
        float Y  = cast(float)yBlocks [ybi][ybpy * 8 + ybpx] + 128.0f;
        float Cb = cast(float)cbBlocks[cbi][cbpy * 8 + cbpx];
        float Cr = cast(float)crBlocks[cri][crpy * 8 + crpx];

        // Convert from YCbCr to RGB
        Color4f col;
        col.r = Y + 1.402f * Cr;
        col.g = Y - 0.34414f * Cb - 0.71414f * Cr;
        col.b = Y + 1.772f * Cb;
        col = col / 255.0f;
        col.a = 1.0f;

        return col;
    }
}


