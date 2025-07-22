import terminal, strformat, strutils, sequtils, tables, json, times, base64, system

import ../[utils, globals]
import ../db/database
import ../task/packer
import ../../common/[types, utils]

import sugar 

# Utility functions 
proc add*(cq: Conquest, agent: Agent) = 
    cq.agents[agent.agentId] = agent

#[
  Agent API
  Functions relevant for dealing with the agent API, such as registering new agents, querying tasks and posting results
]#
proc register*(registrationData: seq[byte]): bool = 

    # The following line is required to be able to use the `cq` global variable for console output
    {.cast(gcsafe).}:

        let agent: Agent = deserializeNewAgent(registrationData)

        # Validate that listener exists        
        if not cq.dbListenerExists(agent.listenerId.toUpperAscii): 
            cq.writeLine(fgRed, styleBright, fmt"[-] {agent.ip} attempted to register to non-existent listener: {agent.listenerId}.", "\n")
            return false

        # # Store agent in database
        if not cq.dbStoreAgent(agent): 
            cq.writeLine(fgRed, styleBright, fmt"[-] Failed to insert agent {agent.agentId} into database.", "\n")
            return false

        cq.add(agent)

        let date = agent.firstCheckin.format("dd-MM-yyyy HH:mm:ss")
        cq.writeLine(fgYellow, styleBright, fmt"[{date}] ", resetStyle, "Agent ", fgYellow, styleBright, agent.agentId, resetStyle, " connected to listener ", fgGreen, styleBright, agent.listenerId, resetStyle, ": ", fgYellow, styleBright, fmt"{agent.username}@{agent.hostname}", "\n") 

    return true

proc getTasks*(checkinData: seq[byte]): seq[seq[byte]] = 

    {.cast(gcsafe).}:

        # Deserialize checkin request to obtain agentId and listenerId 
        let 
            request: Heartbeat = deserializeHeartbeat(checkinData)
            agentId = uuidToString(request.agentId)
            listenerId = uuidToString(request.listenerId)
            timestamp = request.timestamp

        var result: seq[seq[byte]]

        # Check if listener exists
        if not cq.dbListenerExists(listenerId): 
            cq.writeLine(fgRed, styleBright, fmt"[-] Task-retrieval request made to non-existent listener: {listenerId}.", "\n")
            raise newException(ValueError, "Invalid listener.")

        # Check if agent exists
        if not cq.dbAgentExists(agentId): 
            cq.writeLine(fgRed, styleBright, fmt"[-] Task-retrieval request made to non-existent agent: {agentId}.", "\n")
            raise newException(ValueError, "Invalid agent.")

        # Update the last check-in date for the accessed agent
        cq.agents[agentId].latestCheckin = cast[int64](timestamp).fromUnix().local()
        # if not cq.dbUpdateCheckin(agent.toUpperAscii, now().format("dd-MM-yyyy HH:mm:ss")):
        #    return nil

        # Return tasks
        for task in cq.agents[agentId].tasks: 
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