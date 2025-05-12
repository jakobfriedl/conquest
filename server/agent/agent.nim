import terminal, strformat, times
import ../[types, globals]


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
    discard

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
proc notifyAgentRegister*(agent: Agent) = 

    let date: string = now().format("dd-MM-yyyy HH:mm:ss")



    # The following line is required to be able to use the `cq` global variable for console output
    {.cast(gcsafe).}:
        cq.writeLine(fgYellow, styleBright, fmt"[{date}] Agent {agent.name} connected.", "\n") 

#[
    Agent interaction mode
    When interacting with a agent, the following functions are called:
    - addTask, to add a new tasks to the agents task queue
    - getTaskResult, get the result for the task from the agent 
]#