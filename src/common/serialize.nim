import streams, strutils, tables
import ./[types, utils, crypto, sequence]
type 
    Packer* = ref object 
        stream: StringStream

proc initPacker*(): Packer = 
    result = new Packer 
    result.stream = newStringStream()

proc add*[T: uint8 | uint16 | uint32 | uint64](packer: Packer, value: T): Packer {.discardable.} =
    packer.stream.write(value)
    return packer 

proc addData*(packer: Packer, data: openArray[byte]): Packer {.discardable.} = 
    packer.stream.writeData(data[0].unsafeAddr, data.len)
    return packer

proc addArgument*(packer: Packer, arg: TaskArg): Packer {.discardable.} = 
    # Optional argument was passed as "", ignore
    if arg.data.len <= 0: 
        return

    packer.add(arg.argType)

    case cast[ArgType](arg.argType): 
    of STRING, BINARY: 
        # Add length for variable-length data types
        packer.add(cast[uint32](arg.data.len)) 
        packer.addData(arg.data)
    else: 
        packer.addData(arg.data)
    return packer

proc addVarLengthMetadata*(packer: Packer, metadata: seq[byte]): Packer {.discardable.} = 
    # Add length of metadata field
    packer.add(cast[uint32](metadata.len))

    if metadata.len <= 0: 
        # Field is empty (e.g. not domain joined)
        return packer

    # Add content
    packer.addData(metadata)
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
    
    if length <= 0:
        return @[]

    result = newSeq[byte](length)
    let bytesRead = unpacker.stream.readData(result[0].addr, length)
    unpacker.position += bytesRead
    
    if bytesRead != length:
        raise newException(IOError, "Not enough data to read")

proc getKey*(unpacker: Unpacker): Key = 
    var key: Key

    let bytesRead = unpacker.stream.readData(key[0].unsafeAddr, 32)
    unpacker.position += bytesRead
    
    if bytesRead != 32:
        raise newException(IOError, "Not enough data to read key")
    
    return key

proc getIv*(unpacker: Unpacker): Iv = 
    var iv: Iv

    let bytesRead = unpacker.stream.readData(iv[0].unsafeAddr, 12)
    unpacker.position += bytesRead
    
    if bytesRead != 12:
        raise newException(IOError, "Not enough data to read IV")
    
    return iv

proc getAuthenticationTag*(unpacker: Unpacker): AuthenticationTag = 
    var tag: AuthenticationTag
    
    let bytesRead = unpacker.stream.readData(tag[0].unsafeAddr, 16)
    unpacker.position += bytesRead
    
    if bytesRead != 16:
        raise newException(IOError, "Not enough data to read authentication tag")
    
    return tag

proc getArgument*(unpacker: Unpacker): TaskArg = 
    result.argType = unpacker.getUint8()
    
    case cast[ArgType](result.argType):
    of STRING, BINARY:
        # Variable-length fields are prefixed with the content-length
        let length = unpacker.getUint32()
        result.data = unpacker.getBytes(int(length))
    of INT:
        result.data = unpacker.getBytes(4)
    of LONG:
        result.data = unpacker.getBytes(8)
    of BOOL:
        result.data = unpacker.getBytes(1)
    else: 
        discard

proc getVarLengthMetadata*(unpacker: Unpacker): string = 

    # Read length of metadata field
    let length = unpacker.getUint32()
    
    if length <= 0: 
        return ""

    # Read content
    return unpacker.getBytes(int(length)).toString()

# Serialization & Deserialization functions
proc serializeHeader*(packer: Packer, header: Header, bodySize: uint32): seq[byte] = 
    packer
        .add(header.magic)
        .add(header.version)
        .add(header.packetType)
        .add(header.flags)
        .add(bodySize)
        .add(header.agentId)
        .add(header.seqNr) 
        .addData(header.iv) 
        .addData(header.gmac)

    return packer.pack()

proc deserializeHeader*(unpacker: Unpacker): Header=
    return Header(
        magic: unpacker.getUint32(),
        version: unpacker.getUint8(),
        packetType: unpacker.getUint8(),
        flags: unpacker.getUint16(),
        size: unpacker.getUint32(),
        agentId: unpacker.getUint32(),
        seqNr: unpacker.getUint32(),
        iv: unpacker.getIv(),
        gmac: unpacker.getAuthenticationTag()
    )
    