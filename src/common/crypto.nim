import random
import nimcrypto

import ./[utils, types]

proc generateSessionKey*(): Key =
    # Generate a random 256-bit (32-byte) session key for AES-256 encryption
    var key: array[32, byte]
    for i in 0 ..< 32:
        key[i] = byte(rand(255)) 
    return key

proc generateIV*(): Iv =
    # Generate a random 98-bit (12-byte) initialization vector for AES-256 GCM mode
    var iv: array[12, byte]
    for i in 0 ..< 12:
        iv[i] = byte(rand(255)) 
    return iv

proc encrypt*(key: Key, iv: Iv, data: seq[byte], sequenceNumber: uint64): (seq[byte], AuthenticationTag) =
    
    # Encrypt data using AES-256 GCM
    var encData = newSeq[byte](data.len)
    var tag: AuthenticationTag
    
    var ctx: GCM[aes256]
    ctx.init(key, iv, sequenceNumber.toBytes())    
    
    ctx.encrypt(data, encData)
    ctx.getTag(tag)
    ctx.clear()
    
    return (encData, tag)

proc decrypt*(key: Key, iv: Iv, encData: seq[byte], sequenceNumber: uint64): (seq[byte], AuthenticationTag) =
    
    # Decrypt data using AES-256 GCM
    var data = newSeq[byte](encData.len)
    var tag: AuthenticationTag
    
    var ctx: GCM[aes256]
    ctx.init(key, iv, sequenceNumber.toBytes())
    
    ctx.decrypt(encData, data)
    ctx.getTag(tag)
    ctx.clear()
    
    return (data, tag)

