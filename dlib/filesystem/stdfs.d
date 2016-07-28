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

module dlib.filesystem.stdfs;

import core.stdc.stdio;
import std.file;
import std.string;
import dlib.core.memory;
import dlib.core.stream;
import dlib.container.dict;
import dlib.filesystem.filesystem;

version(Posix)
{
    import core.sys.posix.sys.stat;
    import dlib.filesystem.stdposixdir;
}
version(Windows)
{
    import std.stdio;
    import dlib.filesystem.stdwindowsdir;
}

import dlib.text.utils;
import dlib.text.utf16;

// TODO: where is these definitions in druntime?
version(Windows)
{
   extern(C) int _wmkdir(const wchar*);
   extern(C) int _wremove(const wchar*);
   
   extern(Windows) int RemoveDirectoryW(const wchar*);
}

class StdInFileStream: InputStream
{
    FILE* file;
    StreamSize _size;
    bool eof;

    this(FILE* file)
    {
        this.file = file;

        fseek(file, 0, SEEK_END);
        _size = ftell(file);
        fseek(file, 0, SEEK_SET);
        
        eof = false;
    }

    ~this()
    {
        fclose(file);
    }

    StreamPos getPosition() @property
    { 
        return ftell(file);
    }

    bool setPosition(StreamPos p)
    {
        import core.stdc.config : c_long;
        return !fseek(file, cast(c_long)p, SEEK_SET);
    }

    StreamSize size()
    {
        return _size;
    }

    void close()
    {
        fclose(file);
    }

    bool seekable()
    {
        return true;
    }

    bool readable()
    {
        return !eof;
    }

    size_t readBytes(void* buffer, size_t count)
    {
        auto bytesRead = fread(buffer, 1, count, file);
        if (count > bytesRead)
            eof = true;
        return bytesRead;
    }
}

class StdOutFileStream: OutputStream 
{
    FILE* file;
    bool _writeable;

    this(FILE* file)
    {
        this.file = file;
        this._writeable = true;
    }

    ~this()
    {
        fclose(file);
    }
    
    StreamPos getPosition() @property
    {
        return 0;
    }
    
    bool setPosition(StreamPos pos)
    {
        return false;
    }
    
    StreamSize size()
    {
        return 0;
    }
    
    void close()
    {
        fclose(file);
    }
    
    bool seekable()
    {
        return false;
    }
    
    void flush()
    {
        fflush(file); 
    }
    
    bool writeable()
    {
        return _writeable;
    }
    
    size_t writeBytes(const void* buffer, size_t count)
    {
        size_t res = fwrite(buffer, 1, count, file);
        if (res != count)
            _writeable = false;
        return res;
    }
}

class StdIOStream: IOStream
{
    FILE* file;
    StreamSize _size;
    bool _eof;
    bool _writeable;

    this(FILE* file)
    {
        this.file = file;
        this._writeable = true;
        
        fseek(file, 0, SEEK_END);
        this._size = ftell(file);
        fseek(file, 0, SEEK_SET);
        
        this._eof = false;
    }
    
    ~this()
    {
        fclose(file);
    }
    
    StreamPos getPosition() @property
    { 
        return ftell(file);
    }

    bool setPosition(StreamPos p)
    {
        import core.stdc.config : c_long;
        return !fseek(file, cast(c_long)p, SEEK_SET);
    }

    StreamSize size()
    {
        return _size;
    }

    void close()
    {
        fclose(file);
    }

    bool seekable()
    {
        return true;
    }

    bool readable()
    {
        return !_eof;
    }

    size_t readBytes(void* buffer, size_t count)
    {
        auto bytesRead = fread(buffer, 1, count, file);
        if (count > bytesRead)
            _eof = true;
        return bytesRead;
    }
    
    void flush()
    {
        fflush(file); 
    }
    
    bool writeable()
    {
        return _writeable;
    }
    
    size_t writeBytes(const void* buffer, size_t count)
    {
        size_t res = fwrite(buffer, 1, count, file);
        if (res != count)
            _writeable = false;
        return res;
    }
}

class StdFileSystem: FileSystem
{
    Dict!(Directory, string) openedDirs;

    this()
    {
        openedDirs = New!(Dict!(Directory, string));
    }
    
    ~this()
    {
        foreach(k, v; openedDirs)
            Delete(v);
        Delete(openedDirs);
    }

    bool stat(string filename, out FileStat stat)
    {
        if (std.file.exists(filename))
        {
            with(stat)
            {
                isFile = std.file.isFile(filename);
                isDirectory = std.file.isDir(filename);
                sizeInBytes = std.file.getSize(filename);
                getTimes(filename, 
                    modificationTimestamp,
                    modificationTimestamp); 
            }
            return true;
        }
        else
            return false;
    }

    StdInFileStream openForInput(string filename)
    {
        version(Posix)
        {
            FILE* file = fopen(filename.toStringz, "rb"); // TODO: GC-free toStringz replacement
        }
        version(Windows)
        {
            wchar[] filename_utf16 = convertUTF8toUTF16(filename, true);
            wchar[] mode_utf16 = convertUTF8toUTF16("rb", true);
            FILE* file = _wfopen(filename_utf16.ptr, mode_utf16.ptr);
            Delete(filename_utf16);
            Delete(mode_utf16);
        }
        return New!StdInFileStream(file);
    }
    
    StdOutFileStream openForOutput(string filename, uint creationFlags = FileSystem.create)
    {
        version(Posix)
        {
            FILE* file = fopen(filename.toStringz, "wb"); // TODO: GC-free toStringz replacement
        }
        version(Windows)
        {
            wchar[] filename_utf16 = convertUTF8toUTF16(filename, true);
            wchar[] mode_utf16 = convertUTF8toUTF16("wb", true);
            FILE* file = _wfopen(filename_utf16.ptr, mode_utf16.ptr);
            Delete(filename_utf16);
            Delete(mode_utf16);
        }
        return New!StdOutFileStream(file);
    }
    
    StdIOStream openForIO(string filename, uint creationFlags = FileSystem.create)
    {        
        version(Posix)
        {
            FILE* file = fopen(filename.toStringz, "rb+"); // TODO: GC-free toStringz replacement
        }
        version(Windows)
        {
            wchar[] filename_utf16 = convertUTF8toUTF16(filename, true);
            wchar[] mode_utf16 = convertUTF8toUTF16("rb+", true);
            FILE* file = _wfopen(filename_utf16.ptr, mode_utf16.ptr);
            Delete(filename_utf16);
            Delete(mode_utf16);
        }
        return New!StdIOStream(file);
    }

    Directory openDir(string path)
    {
        version(Posix)
        {
            if (path in openedDirs)
            {
                auto d = openedDirs[path];
                //d.reset();
                return d;
            }
            else
            {
                auto dir = New!StdPosixDirectory(path);
                openedDirs[path] = dir;
                return dir;
            }
        }
        version(Windows)
        {
            if (path in openedDirs)
            {
                return openedDirs[path];
            }
            else
            {
                string s = catStr(path, "\\*.*");
                wchar[] ws = convertUTF8toUTF16(s, true);
                Delete(s);
                auto dir = New!StdWindowsDirectory(ws);
                openedDirs[path] = dir;
                return dir;
            }
        }
    }

    bool createDir(string path, bool recursive = true)
    {
        version(Posix)
        {
            int res = mkdir(path.toStringz, 777); // TODO: GC-free toStringz replacement
            return (res == 0);
        }
        version(Windows)
        {
            wchar[] wp = convertUTF8toUTF16(path, true);
            int res = _wmkdir(wp.ptr);
            Delete(wp);
            return (res == 0);
        }
    }

    bool remove(string path, bool recursive = true)
    {
        version(Posix)
        {
            int res = core.stdc.stdio.remove(path.toStringz); // TODO: GC-free toStringz replacement
            return (res == 0);
        }
        version(Windows)
        {
            import std.stdio;
            bool res;
            if (std.file.isDir(path))
            {
                if (recursive)
                foreach(e; openDir(path).contents)
                {
                    string path2 = catStr(path, "\\");
                    string path3 = catStr(path2, e.name);
                    Delete(path2);
                    writeln(path3);
                    this.remove(path3, recursive);
                    Delete(path3);
                }

                wchar[] wp = convertUTF8toUTF16(path, true);
                res = RemoveDirectoryW(wp.ptr) != 0;
                Delete(wp);
            }
            else
            {
                wchar[] wp = convertUTF8toUTF16(path, true);
                res = _wremove(wp.ptr) == 0;
                Delete(wp);
            }  
            return res;
        }
    }
}

string readText(InputStream istrm)
{
    ubyte[] arr = New!(ubyte[])(cast(size_t)istrm.size);
    istrm.fillArray(arr);
    istrm.setPosition(0);
    return cast(string)arr;
}

T readStruct(T)(InputStream istrm) if (is(T == struct))
{
    T res;
    istrm.readBytes(res.ptr, T.sizeof);
    return res;
}
