import macros, system, hashes
import nimcrypto

import ./[types, utils]

#[
    Symmetric AES256 GCM encryption for secure C2 traffic
    Ensures both confidentiality and integrity of the packet 
]#
proc generateBytes*(T: typedesc[Key | Iv]): array =
    var bytes: T
    if randomBytes(bytes) != sizeof(T): 
        raise newException(CatchableError, protect("Failed to generate byte array."))
    return bytes

proc encrypt*(key: Key, iv: Iv, data: seq[byte], sequenceNumber: uint32 = 0): (seq[byte], AuthenticationTag) =
    
    # Encrypt data using AES-256 GCM
    var encData = newSeq[byte](data.len)
    var tag: AuthenticationTag
    
    var ctx: GCM[aes256]
    ctx.init(key, iv, uint32.toBytes(sequenceNumber))    
    
    ctx.encrypt(data, encData)
    ctx.getTag(tag)
    ctx.clear()
    
    return (encData, tag)

proc decrypt*(key: Key, iv: Iv, encData: seq[byte], sequenceNumber: uint32 = 0): (seq[byte], AuthenticationTag) =
    
    # Decrypt data using AES-256 GCM
    var data = newSeq[byte](encData.len)
    var tag: AuthenticationTag
    
    var ctx: GCM[aes256]
    ctx.init(key, iv, uint32.toBytes(sequenceNumber))
    
    ctx.decrypt(encData, data)
    ctx.getTag(tag)
    ctx.clear()
    
    return (data, tag)

proc validateDecryption*(key: Key, iv: Iv, encData: seq[byte], sequenceNumber: uint32, header: Header): seq[byte] = 

    let (decData, gmac) = decrypt(key, iv, encData, sequenceNumber)

    if gmac != header.gmac: 
        raise newException(CatchableError, protect("Invalid authentication tag."))

    return decData

#[
    Key exchange using X25519 and Blake2b
    Elliptic curve cryptography ensures that the actual session key is never sent over the network
    Private keys and shared secrets are wiped from agent memory as soon as possible 
]#
{.compile: "monocypher/monocypher.c".}

# C function imports from (monocypher/monocypher.c)
proc crypto_x25519*(shared_secret: ptr byte, your_secret_key: ptr byte, their_public_key: ptr byte) {.importc, cdecl.}
proc crypto_x25519_public_key*(public_key: ptr byte, secret_key: ptr byte) {.importc, cdecl.}
proc crypto_blake2b_keyed*(hash: ptr byte, hash_size: csize_t, key: ptr byte, key_size: csize_t, message: ptr byte, message_size: csize_t) {.importc, cdecl.}
proc crypto_wipe*(data: ptr byte, size: csize_t) {.importc, cdecl.}

# Generate X25519 public key from private key
proc getPublicKey*(privateKey: Key): Key =
    crypto_x25519_public_key(result[0].addr, privateKey[0].addr)

# Perform X25519 key exchange
proc keyExchange*(privateKey: Key, publicKey: Key): Key =
    crypto_x25519(result[0].addr, privateKey[0].addr, publicKey[0].addr)

# Calculate Blake2b hash
func pointerAndLength*(bytes: openArray[byte]): (ptr[byte], uint) =
    result = (cast[ptr[byte]](unsafeAddr bytes), uint(len(bytes)))

func blake2b*(message: openArray[byte], key: openArray[byte] = []): array[64, byte] =
    let (messagePtr, messageLen) = pointerAndLength(message)
    let (keyPtr, keyLen) = pointerAndLength(key)
    
    crypto_blake2b_keyed(addr result[0], 64, keyPtr, keyLen, messagePtr, messageLen)

# Secure memory wiping
proc wipeKey*(data: var openArray[byte]) =
    if data.len > 0:
        crypto_wipe(data[0].addr, data.len.csize_t)

# Key pair generation
proc generateKeyPair*(): KeyPair = 
    let privateKey = generateBytes(Key) 
    return KeyPair(
        privateKey: privateKey, 
        publicKey: getPublicKey(privateKey)
    )

# Key derivation
proc combineKeys(publicKey, otherPublicKey: Key): Key = 
    # XOR is a commutative operation, that ensures that the order of the public keys does not matter
    for i in 0..<32:
        result[i] = publicKey[i] xor otherPublicKey[i]

proc deriveSessionKey*(keyPair: KeyPair, publicKey: Key): Key =
    var key: Key
    
    # Calculate shared secret (https://monocypher.org/manual/x25519)
    var sharedSecret = keyExchange(keyPair.privateKey, publicKey)

    # Add combined public keys to hash
    let combinedKeys: Key = combineKeys(keyPair.publicKey, publicKey)
    let hashMessage: seq[byte] = string.toBytes(protect("CONQUEST")) & @combinedKeys 

    # Calculate Blake2b hash and extract the first 32 bytes for the AES key (https://monocypher.org/manual/blake2b)
    let hash = blake2b(hashMessage, sharedSecret)
    copyMem(key[0].addr, hash[0].addr, sizeof(Key))

    # Cleanup 
    wipeKey(sharedSecret)

    return key

# Key management
proc writeKeyToDisk*(keyFile: string, key: Key) = 
    let file = open(keyFile, fmWrite)
    defer: file.close()

    let bytesWritten = file.writeBytes(key, 0, sizeof(Key))

    if bytesWritten != sizeof(Key):
        raise newException(ValueError, protect("Invalid key length."))

proc loadKeyPair*(keyFile: string): KeyPair = 
    try: 
        let file = open(keyFile, fmRead)
        defer: file.close()

        var privateKey: Key
        let bytesRead = file.readBytes(privateKey, 0, sizeof(Key))

        if bytesRead != sizeof(Key):
            raise newException(ValueError, protect("Invalid key length."))

        return KeyPair(
            privateKey: privateKey,
            publicKey: getPublicKey(privateKey)
        )

    # Create a new key pair if the private key file is not found 
    except IOError: 
        let keyPair = generateKeyPair() 
        writeKeyToDisk(keyFile, keyPair.privateKey)
        return keyPair