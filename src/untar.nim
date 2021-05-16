import binarylang, strutils, streams, strformat, os
import zip/gzipfiles

type
  TarFormat* = enum
    tfUnk, tfTar, tfTgz, tfLzw, tfLzh, tfXz
  TarFileName* = string
  TgzFileName* = string

struct(posixHeader):
  s: name(100)
  s: mode(8)
  s: uid(8)
  s: gid(8)
  s: size(12)
  s: mtime(12)
  s: chksum(8)
  s: typeflag(1)
  s: linkname(100)
  s: magic(6)
  s: version(2)
  s: uname(32)
  s: gname(32)
  s: devmajor(8)
  s: devminor(8)
  s: prefix(155)
  s: _(12)
  #s: atime(12)
  #s: ctime(12)
  #u8: data(size.parseOctInt)

proc `$`*(h:PosixHeader):string =
  result  = &"Name: {h.name}\n"
  result &= &"Mode: {h.mode}\n"
  result &= &"uid: {h.uid}\n"
  result &= &"gid: {h.gid}\n"
  result &= &"size: {h.size.parseOctInt}\n"
  result &= &"mtime: {h.mtime}\n"
  result &= &"chksum: {h.chksum}\n"
  result &= &"typeflag: {h.typeflag}\n"
  result &= &"linkname: {h.linkname}\n"
  result &= &"magic: {h.magic}\n"
  result &= &"version: {h.version}\n"
  result &= &"uname: {h.uname}\n"
  result &= &"gname: {h.gname}\n"
  result &= &"devmajor: {h.devmajor}\n"
  result &= &"devminor: {h.devminor}\n"
  result &= &"prefix: {h.prefix}\n"        

#[
struct(starHeader):
  s: name(100)
  s: mode(8)
  s: uid(8)
  s: gid(8)
  s: size(12)
  s: mtime(12)
  s: chksum(8)
  s: typeflag(1)
  s: linkname(100)
  s: magic(6)
  s: version(2)
  s: uname(32)
  s: gname(32)
  s: devmajor(8)
  s: devminor(8)
  s: prefix(131)  # This is different
  s: atime(12)    # This is different
  s: ctime(12)    # This is different
]#



proc guessTarFormat*(fname:string):TarFormat =
  #[
  Position: 0
  1F 8B: .tgz
  1F 9D: tar.z (tar zip) Lempel-Ziv-Welch 
  1F a0: tar.z (tar zip) LZH
  FD 37 7A 58 5A 00: .tar.xz

  Position 0x101:
  75 73 74 61 72 00 30 30: 0x101 (tar)
  75 73 74 61 72 20 20 00: 0x101 (tar)  
  ]#
  let fs = newFileStream(fname, fmRead)

  var buffer: array[8, uint8]
  discard fs.readData(buffer.addr, 6)
  #let n1 = fs.readUint8
  if  buffer[0] == 0x1F:
    case buffer[1]:
    of 0x8B: return tfTgz
    of 0x9D: return tfLzw
    of 0xA0: return tfLzh
    else:    return tfUnk
  
  elif buffer[0 .. 5] == [0xFD'u8,0x37, 0x7A, 0x58, 0x5A, 0x00]:
    return tfXz
  
  fs.setPosition(0x101)
  discard fs.readData(buffer.addr, 8)  
  if buffer == [0x75'u8, 0x73, 0x74, 0x61, 0x72, 0x00, 0x30, 0x30] or
     buffer == [0x75'u8, 0x73, 0x74, 0x61, 0x72, 0x20, 0x20, 0x00]:
    return tfTar
  
  else:
    return tfUnk

proc `$`*(format:TarFormat):string =
  case format:
  of tfUnk: "Unknown"
  of tfTar: ".tar"
  of tfTgz: ".tgz"
  of tfLzw: ".tar.z (Lempel-Ziv-Welch)"
  of tfLzh: ".tar.z (LZH)"
  of tfXz: ".tar.xz"



proc roundup(x, v: int): int {.inline.} =
  # Stolen from Nim's osalloc.nim
  result = (x + (v-1)) and not (v-1)
  assert(result >= x)

#struct(fileContent, size:int):
#  s: data(size)



#proc checkEndOfTarFile(filename:TarFileName, pos:int):bool =

type
  TarFile* = object
    name*: string
    header*: PosixHeader
    fileSize*: int
    alignedFileSize*: int
    position*: int

proc `$`(tf:TarFile):string =
  &"Name: {tf.name}   Size: {tf.fileSize}   at position: {tf.position}\n"

proc getFileList*(filename:TarFileName):seq[TarFile] =
  let fbs = newFileBitStream(filename, fmRead)
  defer: close(fbs)
  result = newSeq[TarFile]()
  #let endOfArchive = 
  var flag = true
  while not fbs.atEnd:
    let h = posixHeader.get(fbs)
    if h.name != "": # Only for not empty registers
      # Read the file contents.
      var fileSize = h.size.parseOctInt
      let alignedFileSize = roundup(fileSize, 512)  
      let position = fbs.getPosition 
      result &= TarFile(
          name: h.name,
          header: h,
          fileSize: fileSize,
          alignedFileSize: alignedFileSize,
          position: position
      )   
      fbs.setPosition(position + alignedFileSize)

proc extractAllFiles( filename:TarFileName, destDir:string = "" ) =
  createDir(destDir)
  let files = getFileList(filename)

  for fname in files:
    let fs = newFileStream( filename, fmRead)
    defer: fs.close

    fs.setPosition(fname.position)
    let data = fs.readStr(fname.alignedFileSize)[0 ..< fname.fileSize] 

    var fbw = newFileStream(destdir / fname.name, fmWrite)
    defer: close(fbw)
    fbw.write(data)

proc uncompress*( filename: TgzFileName, destFile:string = "") =
  #createDir(destDir)
  let gzfs = newGzFileStream(filename)
  let (dir,name,ext) = splitFile(filename)
  var newFile = dir / name & ".tar"
  if destFile != "":
    newFile = destFile
  let fs = newFileStream(newFile, fmWrite)
  defer: fs.close()

  while not gzfs.atEnd():
    fs.write( gzfs.readAll() )

when isMainModule:
  import cligen

  proc showHelp() =
    let txt = """
Tar

Usage:
  tar [optional-params] [paths: string...]
An API call doc comment
Options:
  -h, --help                    print this cligen-erated help
  --help-syntax                 advanced: prepend,plurals,..
  -f=, --foo=    int     1      set foo
  -b=, --bar=    float   2.0    set bar
  --baz=         string  "hi"   set baz
  -v, --verb     bool    false  set verb
"""    
    echo txt

  proc cli(list:bool = false, paths: seq[string]) =
    if paths.len == 0:
      showHelp()
      quit(0)      

    #let filename = "examples/tar.tgz"
    let filename = paths[0]
    if not fileExists(filename):
      echo &"Filename: '{filename}' does not exist"
      quit(1)


    
    let fbs = newFileBitStream(filename, fmRead)
    defer: close(fbs)

    let tarFormat = guessTarFormat(filename)  
    #echo $tarFormat

    # TAR file
    if tarFormat == tfTar:
      let tarFile = filename.TarFileName
      #let fileList = getFileList(tarFile)
      extractAllFiles( tarFile, "examples/dstDir" )

    elif tarFormat == tfTgz:
      let tarFile = filename.TgzFileName
      
      # By default, uncompress the file with the same name
      if paths.len == 1:  
        uncompress( tarFile )

  dispatch( cli )