import terminal, strformat
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
  build            Build an agent to connect to an active listener.
  interact         Interact with an active agent.

Options:
  -h, --help""")

proc agentList*(cq: Conquest, args: varargs[string]) = 
    let agents = cq.dbGetAllAgents()
    cq.drawTable(agents)

proc agentBuild*(cq: Conquest, args: varargs[string]) = 
    discard

# Switch to interact mode
proc agentInteract*(cq: Conquest, args: varargs[string]) = 

    cq.setIndicator("[AGENT] (username@hostname)> ")
    cq.setStatusBar(@[("mode", "interact"), ("listeners", "X"), ("agents", "4")])    

    var command: string = cq.readLine()

    discard

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
        if not cq.listenerExists(agent.listener): 
            cq.writeLine(fgRed, styleBright, fmt"[-] Agent from {agent.ip} attempted to register to non-existent listener: {agent.listener}.", "\n")
            return false

        # Store agent in database
        if not cq.dbStoreAgent(agent): 
            cq.writeLine(fgRed, styleBright, fmt"[-] Failed to insert agent {agent.name} into database.", "\n")
            return false

        cq.add(agent.name, agent)
        cq.writeLine(fgYellow, styleBright, fmt"[{agent.firstCheckin}] ", resetStyle, "Agent ", fgYellow, styleBright, agent.name, resetStyle, " connected to listener ", fgGreen, styleBright, agent.listener, resetStyle, ": ", fgYellow, styleBright, fmt"{agent.username}@{agent.hostname}", "\n") 

    return true
#[
    Agent interaction mode
    When interacting with a agent, the following functions are called:
    - addTask, to add a new tasks to the agents task queue
    - getTaskResult, get the result for the task from the agent 
]#