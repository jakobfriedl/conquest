import macros, hashes
import strutils, nimcrypto

import ./types

proc toString*(T: type Bytes, data: openArray[byte]): string =
    result = newString(data.len)
    for i, b in data:
        result[i] = char(b)

proc toBytes*(T: type string, data: string): seq[byte] =
    result = newSeq[byte](data.len)
    for i, c in data:
        result[i] = byte(c.ord)

#[
    Compile-time string encryption using simple XOR
    This is done to hide sensitive strings, such as C2 profile settings in the binary 
]#
proc calculate(str: string, key: int): string {.noinline.} = 
    var k = key 
    var bytes = string.toBytes(str)
    for i in 0 ..< bytes.len:
        for f in [0, 8, 16, 24]: 
            bytes[i] = bytes[i] xor uint8((k shr f) and 0xFF)
        k = k +% 1
    return Bytes.toString(bytes)

# Generate a XOR key at compile-time. The `and` operation ensures that a positive integer is the result
var key {.compileTime.}: int = hash(CompileTime & CompileDate) and 0x7FFFFFFF

macro protect*(str: untyped): untyped = 
    var encStr = calculate($str, key)
    result = quote do: 
        calculate(`encStr`, `key`)
    
    # Alternate the XOR key using the FNV prime (1677619)
    key = (key *% 1677619) and 0x7FFFFFFF

#[
    Utility functions
]#
proc toUuid*(T: type string, uuid: string): Uuid = 
    return fromHex[uint32](uuid)

proc toString*(T: type Uuid, uuid: Uuid): string = 
    return uuid.toHex(8)

proc generateUUID*(): string = 
    # Create a 4-byte HEX UUID string (8 characters)
    var uuid: array[4, byte]
    if randomBytes(uuid) != 4: 
        raise newException(CatchableError, protect("Failed to generate UUID."))
    return uuid.toHex().toUpperAscii()

proc toUint32*(T: type Bytes, data: seq[byte]): uint32 =
    if data.len != 4:
        raise newException(ValueError, protect("Expected 4 bytes for uint32"))
    
    return uint32(data[0]) or 
           (uint32(data[1]) shl 8) or 
           (uint32(data[2]) shl 16) or 
           (uint32(data[3]) shl 24)

proc toHexDump*(data: seq[byte]): string =
   for i, b in data:
       result.add(b.toHex(2))
       if i < data.len - 1:
           if (i + 1) mod 4 == 0:
               result.add(" | ")  # Add | every 4 bytes
           else:
               result.add(" ")    # Regular space

proc toBytes*(T: type uint16, value: uint16): seq[byte] =
    return @[
        byte(value and 0xFF),
        byte((value shr 8) and 0xFF)
    ]

proc toBytes*(T: type uint32, value: uint32): seq[byte] =
    return @[
        byte(value and 0xFF),
        byte((value shr 8) and 0xFF),
        byte((value shr 16) and 0xFF),
        byte((value shr 24) and 0xFF)
    ]

proc toBytes*(T: type uint64, value: uint64): seq[byte] =
    return @[
        byte(value and 0xFF),
        byte((value shr 8) and 0xFF),
        byte((value shr 16) and 0xFF),
        byte((value shr 24) and 0xFF),
        byte((value shr 32) and 0xFF),
        byte((value shr 40) and 0xFF),
        byte((value shr 48) and 0xFF),
        byte((value shr 56) and 0xFF)
    ]

proc toKey*(value: string): Key = 
    if value.len != 32:
        raise newException(ValueError, protect("Invalid key length."))
  
    copyMem(result[0].addr, value[0].unsafeAddr, 32)