import system
import ./utils
import ../types/common

# Monocypher C function imports from (monocypher/monocypher.c)
{.compile: protect("monocypher/monocypher.c").}
proc crypto_aead_lock*(cipher_text: ptr byte, mac: ptr byte, key: ptr byte, nonce: ptr byte, ad: ptr byte, ad_size: csize_t, plain_text: ptr byte, text_size: csize_t) {.importc, cdecl.}
proc crypto_aead_unlock*(plain_text: ptr byte, mac: ptr byte, key: ptr byte, nonce: ptr byte, ad: ptr byte, ad_size: csize_t, cipher_text: ptr byte, text_size: csize_t): cint {.importc, cdecl.}
proc crypto_x25519*(shared_secret: ptr byte, your_secret_key: ptr byte, their_public_key: ptr byte) {.importc, cdecl.}
proc crypto_x25519_public_key*(public_key: ptr byte, secret_key: ptr byte) {.importc, cdecl.}
proc crypto_blake2b_keyed*(hash: ptr byte, hash_size: csize_t, key: ptr byte, key_size: csize_t, message: ptr byte, message_size: csize_t) {.importc, cdecl.}
proc crypto_wipe*(data: ptr byte, size: csize_t) {.importc, cdecl.}

#[
    Symmetric encryption using ChaCha20-Poly1305
    Ensures both confidentiality and integrity of the packet using a message authentication code (MAC)
     - https://monocypher.org/manual/aead
]#

proc encrypt*(key: Key, nonce: Nonce, data: seq[byte], sequenceNumber: uint32 = 0): (seq[byte], AuthenticationTag) =
    var encData = newSeq[byte](data.len)
    var mac: AuthenticationTag
    let aad = uint32.toBytes(sequenceNumber)

    crypto_aead_lock(
        addr encData[0],                # Encrypted data
        addr mac[0],                    # Authentication tag 
        addr key[0],                    # Encryption key 
        addr nonce[0],                  # Nonce
        addr aad[0],                    # Additional authentication data: sequence number
        cast[csize_t](aad.len()),       # AAD length
        addr data[0],                   # Plaintext data 
        cast[csize_t](data.len())       # Plaintext length
    )
    
    return (encData, mac)

proc decrypt*(key: Key, nonce: Nonce, encData: seq[byte], sequenceNumber: uint32 = 0, mac: AuthenticationTag): seq[byte] =
    var data = newSeq[byte](encData.len)
    let aad = uint32.toBytes(sequenceNumber)

    if crypto_aead_unlock(
        addr data[0],                   # Decrypted data
        addr mac[0],                    # Authentication tag to validate against
        addr key[0],                    # Encryption key 
        addr nonce[0],                  # Nonce 
        addr aad[0],                    # Additional authentication data: sequence number
        cast[csize_t](aad.len()),       # AAD length 
        addr encData[0],                # Ciphertext data
        cast[csize_t](encData.len())    # Ciphertext length 
    ) != 0:
        crypto_wipe(addr data[0], cast[csize_t](data.len()))
        raise newException(CatchableError, protect("Invalid authentication tag."))
        
    return data

#[
    Key exchange using X25519 and Blake2b
    Elliptic curve cryptography ensures that the actual session key is never sent over the network
    Private keys and shared secrets are wiped from agent memory as soon as possible 
]#

# Generate X25519 public key from private key
proc getPublicKey*(privateKey: Key): Key =
    crypto_x25519_public_key(addr result[0], addr privateKey[0])

# Perform X25519 key exchange
proc keyExchange*(privateKey: Key, publicKey: Key): Key =
    crypto_x25519(addr result[0], addr privateKey[0], addr publicKey[0])

# Calculate Blake2b hash
func pointerAndLength*(bytes: openArray[byte]): (ptr[byte], uint) =
    result = (cast[ptr[byte]](addr bytes), uint(len(bytes)))

func blake2b*(message: openArray[byte], key: openArray[byte] = []): array[64, byte] =
    let (messagePtr, messageLen) = pointerAndLength(message)
    let (keyPtr, keyLen) = pointerAndLength(key)
    
    crypto_blake2b_keyed(addr result[0], 64, keyPtr, keyLen, messagePtr, messageLen)

# Secure memory wiping
proc wipeKey*(data: var openArray[byte]) =
    if data.len > 0:
        crypto_wipe(addr data[0], data.len.csize_t)

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
    copyMem(addr key[0], addr hash[0], sizeof(Key))

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