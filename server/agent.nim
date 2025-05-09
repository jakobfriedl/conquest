import ./types

proc agentUsage*(console: Console) = 
    console.writeLine("""Manage, build and interact with agents.

Usage:
  agent [options] COMMAND

Commands:

  list             List all agents.
  build            Build an agent to connect to an active listener.
  interact         Interact with an active listener.

Options:
  -h, --help""")

proc agentList*(console: Console, args: varargs[string]) = 
    discard

proc agentBuild*(console: Console, args: varargs[string]) = 
    discard

proc agentInteract*(console: Console, args: varargs[string]) = 

    console.setIndicator("[AGENT] (username@hostname)> ")
    console.setStatusBar(@[("mode", "interact"), ("listeners", "X"), ("agents", "4")])    

    var command: string = console.readLine()

    discard