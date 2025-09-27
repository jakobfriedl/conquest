import terminal, strformat, strutils, tables, times, system, parsetoml, prompt

import ./task
import ../utils
import ../core/logger
import ../db/database
import ../../common/types
import ../websocket

# Utility functions
proc addMultiple*(cq: Conquest, agents: seq[Agent]) = 
    for a in agents: 
        cq.agents[a.agentId] = a

proc delAgent*(cq: Conquest, agentName: string) = 
    cq.agents.del(agentName)

proc getAgentsAsSeq*(cq: Conquest): seq[Agent] = 
    var agents: seq[Agent] = @[]
    for agent in cq.agents.values:
        agents.add(agent)
    return agents

#[
    Agent management
]# 
proc agentUsage*(cq: Conquest) = 
    cq.output("""Manage, build and interact with agents.

Usage:
  agent [options] COMMAND

Commands:

  list             List all agents.
  info             Display details for a specific agent.
  kill             Terminate the connection of an active listener and remove it from the interface.
  interact         Interact with an active agent.
  build            Generate a new agent to connect to an active listener.

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
            cq.error(fmt"Listener {listener.toUpperAscii} does not exist.")
            return

        cq.drawTable(cq.dbGetAllAgentsByListener(listener.toUpperAscii))


# Display agent properties and details
proc agentInfo*(cq: Conquest, name: string) = 
    # Check if agent supplied via -n parameter exists in database
    if not cq.dbAgentExists(name.toUpperAscii): 
        cq.error(fmt"Agent {name.toUpperAscii} does not exist.")
        return

    let agent = cq.agents[name.toUpperAscii]

    # TODO: Improve formatting
    cq.output(fmt"""
Agent name (UUID):     {agent.agentId}
Connected to listener: {agent.listenerId}
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
First checkin:         {agent.firstCheckin.format("dd-MM-yyyy HH:mm:ss")}
Latest checkin:        {agent.latestCheckin.format("dd-MM-yyyy HH:mm:ss")}
""")

# Terminate agent and remove it from the database
proc agentKill*(cq: Conquest, name: string) =

    # Check if agent supplied via -n parameter exists in database
    if not cq.dbAgentExists(name.toUpperAscii): 
        cq.error(fmt"Agent {name.toUpperAscii} does not exist.")
        return

    # TODO: Stop the process of the agent on the target system
    # TODO: Add flag to self-delete executable after killing agent


    # Remove the agent from the database
    if not cq.dbDeleteAgentByName(name.toUpperAscii): 
        cq.error("Failed to terminate agent: ", getCurrentExceptionMsg())
        return

    cq.delAgent(name)
    cq.success("Terminated agent ", fgYellow, styleBright, name.toUpperAscii, resetStyle, ".")

# Switch to interact mode
proc agentInteract*(cq: Conquest, name: string) = 

    # Verify that agent exists
    if not cq.dbAgentExists(name.toUpperAscii): 
        cq.error(fmt"Agent {name.toUpperAscii} does not exist.")
        return

    let agent = cq.agents[name.toUpperAscii]
    var command: string = ""

    # Change prompt indicator to show agent interaction
    cq.interactAgent = agent
    cq.prompt.setIndicator(fmt"[{agent.agentId}]> ")
    cq.prompt.setStatusBar(@[("[mode]", "interact"), ("[username]", fmt"{agent.username}"), ("[hostname]", fmt"{agent.hostname}"), ("[ip]", fmt"{agent.ip}"), ("[domain]", fmt"{agent.domain}")])    

    cq.info("Started interacting with agent ", fgYellow, styleBright, agent.agentId, resetStyle, ". Type 'help' to list available commands.\n")

    while command.replace(" ", "") != "back": 
        command = cq.prompt.readLine()
        cq.handleAgentCommand(name, command)
    
    # Reset interactAgent field after interaction with agent is ended using 'back' command
    cq.interactAgent = nil 

