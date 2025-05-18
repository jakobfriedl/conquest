import terminal, strformat, strutils, tables
import ./commands
import ../[types, globals, utils]
import ../db/database


#[ 
    Agent management mode
    These console commands allow dealing with agents from the Conquest framework's prompt interface
]#
proc agentUsage*(cq: Conquest) = 
    cq.writeLine("""Manage, build and interact with agents.

Usage:
  agent [options] COMMAND

Commands:

  list             List all agents.
  info             Display details for a specific agent.
  kill             Terminate the connection of an active listener and remove it from the interface.
  interact         Interact with an active agent.

Options:
  -h, --help""")

# List agents
proc agentList*(cq: Conquest, listener: string) =

    # If no argument is passed via -n, list all agents, otherwise only display agents connected to a specific listener
    if listener == "": 
        cq.drawTable(cq.dbGetAllAgents())
    else: 
        # Check if listener exists
        if not cq.dbListenerExists(listener.toUpperAscii): 
            cq.writeLine(fgRed, styleBright, fmt"[-] Listener {listener.toUpperAscii} does not exist.")
            return

        cq.drawTable(cq.dbGetAllAgentsByListener(listener.toUpperAscii))

# Display agent properties and details
proc agentInfo*(cq: Conquest, name: string) = 
    # Check if agent supplied via -n parameter exists in database
    if not cq.dbAgentExists(name.toUpperAscii): 
        cq.writeLine(fgRed, styleBright, fmt"[-] Agent {name.toUpperAscii} does not exist.")
        return

    let agent = cq.agents[name.toUpperAscii]

    # TODO: Improve formatting
    cq.writeLine(fmt"""
Agent name (UUID):     {agent.name}
Connected to listener: {agent.listener}
──────────────────────────────────────────
Username:              {agent.username}
Hostname:              {agent.hostname}
Domain:                {agent.domain}
IP-Address:            {agent.ip}
Operating system:      {agent.os}
──────────────────────────────────────────
Process name:          {agent.process}
Process ID:            {$agent.pid}
Process elevated:      {$agent.elevated}
First checkin:         {agent.firstCheckin}
    """)

# Terminate agent and remove it from the database
proc agentKill*(cq: Conquest, name: string) =

    # Check if agent supplied via -n parameter exists in database
    if not cq.dbAgentExists(name.toUpperAscii): 
        cq.writeLine(fgRed, styleBright, fmt"[-] Agent {name.toUpperAscii} does not exist.")
        return

    # TODO: Stop the process of the agent on the target system
    # TODO: Add flag to self-delete executable after killing agent


    # Remove the agent from the database
    if not cq.dbDeleteAgentByName(name.toUpperAscii): 
        cq.writeLine(fgRed, styleBright, "[-] Failed to terminate agent: ", getCurrentExceptionMsg())
        return

    cq.delAgent(name)
    cq.writeLine(fgYellow, styleBright, "[+] ", resetStyle, "Terminated agent ", fgYellow, styleBright, name.toUpperAscii, resetStyle, ".")

# Switch to interact mode
proc agentInteract*(cq: Conquest, name: string) = 

    # Verify that agent exists
    if not cq.dbAgentExists(name.toUpperAscii): 
        cq.writeLine(fgRed, styleBright, fmt"[-] Agent {name.toUpperAscii} does not exist.")
        return

    let agent = cq.agents[name.toUpperAscii]
    var command: string = ""

    # Change prompt indicator to show agent interaction
    cq.setIndicator(fmt"[{agent.name}]> ")
    cq.setStatusBar(@[("[mode]", "interact"), ("[username]", fmt"{agent.username}"), ("[hostname]", fmt"{agent.hostname}"), ("[ip]", fmt"{agent.ip}"), ("[domain]", fmt"{agent.domain}")])    
    cq.writeLine(fgYellow, "[+] ", resetStyle, fmt"Started interacting with agent ", fgYellow, agent.name, resetStyle, ". Type 'help' to list available commands.\n")
    cq.interactAgent = agent

    while command != "exit": 
        command = cq.readLine()
        cq.withOutput(handleAgentCommand, command)

    cq.interactAgent = nil 

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
            cq.writeLine(fgRed, styleBright, fmt"[-] Agent from {agent.ip} attempted to register to non-existent listener: {agent.listener}.", "\n")
            return false

        # Store agent in database
        if not cq.dbStoreAgent(agent): 
            cq.writeLine(fgRed, styleBright, fmt"[-] Failed to insert agent {agent.name} into database.", "\n")
            return false

        cq.add(agent)
        cq.writeLine(fgYellow, styleBright, fmt"[{agent.firstCheckin}] ", resetStyle, "Agent ", fgYellow, styleBright, agent.name, resetStyle, " connected to listener ", fgGreen, styleBright, agent.listener, resetStyle, ": ", fgYellow, styleBright, fmt"{agent.username}@{agent.hostname}", "\n") 

    return true
    
#[
    Agent interaction mode
    When interacting with a agent, the following functions are called:
    - addTask, to add a new tasks to the agents task queue
    - getTaskResult, get the result for the task from the agent 
]#