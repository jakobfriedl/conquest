import system
import nimcrypto
import nimcrypto/blake2
from ed25519 import keyExchange, createKeyPair, seed
# from monocypher import crypto_key_exchange_public_key, crypto_key_exchange, crypto_blake2b, crypto_wipe

import ./[utils, types]

#[
    Symmetric AES256 GCM encryption for secure C2 traffic
    Ensures both confidentiality and integrity of the packet 
]#
proc generateKeyPair*(): KeyPair =
    let keyPair = createKeyPair(seed())

    return KeyPair(
        privateKey: keyPair.privateKey,
        publicKey: keyPair.publicKey
    )

proc generateIV*(): Iv =
    # Generate a random 98-bit (12-byte) initialization vector for AES-256 GCM mode
    var iv: Iv
    if randomBytes(iv) != 12: 
        raise newException(CatchableError, "Failed to generate IV.")
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

#[
    ECDHE key exchange using ed25519
]# 
proc loadKeys*(privateKeyFile, publicKeyFile: string): KeyPair = 
    let filePrivate = open(privateKeyFile, fmRead)
    defer: filePrivate.close()

    var privateKey: PrivateKey
    var bytesRead = filePrivate.readBytes(privateKey, 0, sizeof(PrivateKey))

    if bytesRead != sizeof(PrivateKey):
        raise newException(ValueError, "Invalid private key length.")

    let filePublic = open(publicKeyFile, fmRead)
    defer: filePublic.close()

    var publicKey: PublicKey
    bytesRead = filePublic.readBytes(publicKey, 0, sizeof(PublicKey))

    if bytesRead != sizeof(PublicKey):
        raise newException(ValueError, "Invalid public key length.")

    return KeyPair(
        privateKey: privateKey,
        publicKey: publicKey
    )

proc writeKey*[T: PublicKey | PrivateKey](keyFile: string, key: T) = 
    let file = open(keyFile, fmWrite)
    defer: file.close()

    let bytesWritten = file.writeBytes(key, 0, sizeof(T))

    if bytesWritten != sizeof(T):
        raise newException(ValueError, "Invalid key length.")

proc combineKeys(publicKey, otherPublicKey: Key): Key = 
    # XOR is a commutative operation, that ensures that the order of the public keys does not matter
    for i in 0..<32:
        result[i] = publicKey[i] xor otherPublicKey[i]

proc deriveSessionKey*(keyPair: KeyPair, publicKey: Key): Key =
    var key: Key

    # Calculate shared secret (https://monocypher.org/manual/x25519)
    let sharedSecret = keyExchange(publicKey, keyPair.privateKey)

    # Add combined public keys to hash
    let combinedKeys: Key = combineKeys(keyPair.publicKey, publicKey)

    # Calculate Blake2b hash to derive session key
    var ctx: blake2_512
    ctx.init()
    ctx.update(sharedSecret)
    ctx.update("CONQUEST".toBytes() & @combinedKeys)

    let hash = ctx.finish
    let bytes = hash.data[0..<sizeof(Key)]
    copyMem(key[0].addr, bytes[0].addr, sizeof(Key))

    # Cleanup 
    zeroMem(sharedSecret[0].addr, sharedSecret.len)

    return key