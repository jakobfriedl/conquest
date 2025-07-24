import strutils, sequtils, strformat
import nimcrypto

import ./types

proc generateUUID*(): string = 
    # Create a 4-byte HEX UUID string (8 characters)
    var uuid: array[4, byte]
    if randomBytes(uuid) != 4: 
        raise newException(CatchableError, "Failed to generate UUID.")
    return uuid.toHex().toUpperAscii()

proc uuidToUint32*(uuid: string): uint32 = 
    return fromHex[uint32](uuid)

proc uuidToString*(uuid: uint32): string = 
    return uuid.toHex(8)

proc toString*(data: seq[byte]): string =
    result = newString(data.len)
    for i, b in data:
        result[i] = char(b)

proc toBytes*(data: string): seq[byte] =
    result = newSeq[byte](data.len)
    for i, c in data:
        result[i] = byte(c.ord)

proc toUint32*(data: seq[byte]): uint32 =
    if data.len != 4:
        raise newException(ValueError, "Expected 4 bytes for uint32")
    
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

proc toBytes*(value: uint16): seq[byte] =
    return @[
        byte(value and 0xFF),
        byte((value shr 8) and 0xFF)
    ]

proc toBytes*(value: uint32): seq[byte] =
    return @[
        byte(value and 0xFF),
        byte((value shr 8) and 0xFF),
        byte((value shr 16) and 0xFF),
        byte((value shr 24) and 0xFF)
    ]

proc toBytes*(value: uint64): seq[byte] =
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
        raise newException(ValueError, "Invalid key length.")
  
    copyMem(result[0].addr, value[0].unsafeAddr, 32)