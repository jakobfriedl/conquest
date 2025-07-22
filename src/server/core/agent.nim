import terminal, strformat, strutils, tables, times, system, osproc, streams

import ../utils
import ../task/dispatcher
import ../db/database
import ../../common/[types, utils]

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
    cq.setIndicator(fmt"[{agent.agentId}]> ")
    cq.setStatusBar(@[("[mode]", "interact"), ("[username]", fmt"{agent.username}"), ("[hostname]", fmt"{agent.hostname}"), ("[ip]", fmt"{agent.ip}"), ("[domain]", fmt"{agent.domain}")])    
    cq.writeLine(fgYellow, styleBright, "[+] ", resetStyle, fmt"Started interacting with agent ", fgYellow, styleBright, agent.agentId, resetStyle, ". Type 'help' to list available commands.\n")
    cq.interactAgent = agent

    while command.replace(" ", "") != "back": 
        command = cq.readLine()
        cq.withOutput(handleAgentCommand, command)

    cq.interactAgent = nil 

# Agent generation 
proc agentBuild*(cq: Conquest, listener, sleep, payload: string) =

    # Verify that listener exists
    if not cq.dbListenerExists(listener.toUpperAscii): 
        cq.writeLine(fgRed, styleBright, fmt"[-] Listener {listener.toUpperAscii} does not exist.")
        return

    let listener = cq.listeners[listener.toUpperAscii] 

    # Create/overwrite nim.cfg file to set agent configuration 
    let agentConfigFile = fmt"../src/agents/{payload}/nim.cfg"   

    # Parse IP Address and store as compile-time integer to hide hardcoded-strings in binary from `strings` command
    let (first, second, third, fourth) = parseOctets(listener.address)

    # The following shows the format of the agent configuration file that defines compile-time variables 
    let config = fmt"""
    # Agent configuration 
    -d:ListenerUuid="{listener.listenerId}"
    -d:Octet1="{first}"
    -d:Octet2="{second}"
    -d:Octet3="{third}"
    -d:Octet4="{fourth}"
    -d:ListenerPort={listener.port}
    -d:SleepDelay={sleep}
    """.replace("    ", "")
    writeFile(agentConfigFile, config)

    cq.writeLine(fgBlack, styleBright, "[*] ", resetStyle, "Configuration file created.")

    # Build agent by executing the ./build.sh script on the system.
    let agentBuildScript = fmt"../src/agents/{payload}/build.sh"    

    cq.writeLine(fgBlack, styleBright, "[*] ", resetStyle, "Building agent...")
    
    try:
        # Using the startProcess function from the 'osproc' module, it is possible to retrieve the output as it is received, line-by-line instead of all at once
        let process = startProcess(agentBuildScript, options={poUsePath, poStdErrToStdOut})
        let outputStream = process.outputStream

        var line: string
        while outputStream.readLine(line):
            cq.writeLine(line) 

        let exitCode = process.waitForExit()

        # Check if the build succeeded or not
        if exitCode == 0:
            cq.writeLine(fgGreen, "[+] ", resetStyle, "Agent payload generated successfully.")
        else:
            cq.writeLine(fgRed, styleBright, "[-] ", resetStyle, "Build script exited with code ", $exitCode)

    except CatchableError as err:
        cq.writeLine(fgRed, styleBright, "[-] ", resetStyle, "An error occurred: ", err.msg)

