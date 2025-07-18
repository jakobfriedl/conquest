import streams, strutils
import ./types

type 
    Packer* = ref object 
        stream: StringStream

proc initTaskPacker*(): Packer = 
    result = new Packer 
    result.stream = newStringStream()

proc add*[T: uint8 | uint16 | uint32 | uint64](packer: Packer, value: T): Packer {.discardable.} =
    packer.stream.write(value)
    return packer 

proc addData*(packer: Packer, data: openArray[byte]): Packer {.discardable.} = 
    packer.stream.writeData(data[0].unsafeAddr, data.len)
    return packer

proc addArgument*(packer: Packer, arg: TaskArg): Packer {.discardable.} = 
    
    if arg.data.len <= 0: 
        # Optional argument was passed as "", ignore
        return

    packer.add(arg.argType)

    case arg.argType: 
    of cast[uint8](STRING), cast[uint8](BINARY): 
        # Add length for variable-length data types
        packer.add(cast[uint32](arg.data.len)) 
        packer.addData(arg.data)
    else: 
        packer.addData(arg.data)
    return packer

proc pack*(packer: Packer): seq[byte] = 
    packer.stream.setPosition(0) 
    let data = packer.stream.readAll() 
    
    result = newSeq[byte](data.len)
    for i, c in data:
        result[i] = byte(c.ord)
    
    packer.stream.setPosition(0) 

proc reset*(packer: Packer): Packer {.discardable.}  = 
    packer.stream.close()
    packer.stream = newStringStream()
    return packer

type 
    Unpacker* = ref object 
        stream: StringStream
        position: int 

proc initUnpacker*(data: string): Unpacker = 
    result = new Unpacker
    result.stream = newStringStream(data)
    result.position = 0

proc getUint8*(unpacker: Unpacker): uint8 =
    result = unpacker.stream.readUint8()
    unpacker.position += 1

proc getUint16*(unpacker: Unpacker): uint16 =
    result = unpacker.stream.readUint16()
    unpacker.position += 2

proc getUint32*(unpacker: Unpacker): uint32 =
    result = unpacker.stream.readUint32()
    unpacker.position += 4

proc getUint64*(unpacker: Unpacker): uint64 =
    result = unpacker.stream.readUint64()
    unpacker.position += 8

proc getBytes*(unpacker: Unpacker, length: int): seq[byte] = 
    result = newSeq[byte](length)
    let bytesRead = unpacker.stream.readData(result[0].addr, length)
    unpacker.position += bytesRead
    
    if bytesRead != length:
        raise newException(IOError, "Not enough data to read")

proc getArgument*(unpacker: Unpacker): TaskArg = 
    result.argType = unpacker.getUint8()
    
    case result.argType:
    of cast[uint8](STRING), cast[uint8](BINARY):
        # Variable-length fields are prefixed with the content-length
        let length = unpacker.getUint32()
        result.data = unpacker.getBytes(int(length))
    of cast[uint8](INT):
        result.data = unpacker.getBytes(4)
    of cast[uint8](LONG):
        result.data = unpacker.getBytes(8)
    of cast[uint8](BOOL):
        result.data = unpacker.getBytes(1)
    else: 
        discard