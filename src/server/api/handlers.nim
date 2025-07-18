import terminal, strformat, strutils, sequtils, tables, json, times, base64, system

import ../[utils, globals]
import ../db/database
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
        return cq.agents[agent.toUpperAscii].tasks

proc handleResult*(listener, agent, task: string, taskResult: TaskResult) = 

    {.cast(gcsafe).}:

        let date: string = now().format("dd-MM-yyyy HH:mm:ss")
        
        if taskResult.status == cast[uint8](STATUS_FAILED): 
            cq.writeLine(fgBlack, styleBright, fmt"[{date}]", fgRed, styleBright, " [-] ", resetStyle, fmt"Task {task} failed.")

            if taskResult.data.len != 0: 
                cq.writeLine(fgBlack, styleBright, fmt"[{date}]", fgRed, styleBright, " [-] ", resetStyle, "Output:")

                # Split result string on newline to keep formatting
                # for line in decode(taskResult.data).split("\n"):
                #     cq.writeLine(line)
            else: 
                cq.writeLine()

        else:  
            cq.writeLine(fgBlack, styleBright, fmt"[{date}]", fgGreen, " [+] ", resetStyle, fmt"Task {task} finished.")
            
            if taskResult.data.len != 0: 
                cq.writeLine(fgBlack, styleBright, fmt"[{date}]", fgGreen, " [+] ", resetStyle, "Output:")

                # Split result string on newline to keep formatting
                # for line in decode(taskResult.data).split("\n"):
                #     cq.writeLine(line)
            else: 
                cq.writeLine()
        
        # Update task queue to include all tasks, except the one that was just completed
        # cq.agents[agent].tasks = cq.agents[agent].tasks.filterIt(it.id != task)

        return 