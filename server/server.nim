import prompt, terminal
import argparse
import strutils, strformat, times, system, tables

import ./[types, globals]
import agent/agent, listener/listener, db/database

#[
    Argument parsing
]# 
var parser = newParser: 
    help("Conquest Command & Control")

    command("listener"):
        help("Manage, start and stop listeners.")

        command("list"): 
            help("List all active listeners.")
        command("start"): 
            help("Starts a new HTTP listener.")
            option("-h", "-host", default=some("0.0.0.0"), help="IPv4 address to listen on.", required=false)
            option("-p", "-port", help="Port to listen on.", required=true)
            # flag("--dns", help="Use the DNS protocol for C2 communication.")
            # flag("--doh", help="Use DNS over HTTPS for C2 communication.)
        command("stop"):
            help("Stop an active listener.")
            option("-n", "-name", help="Name of the listener to stop.", required=true)
    
    command("agent"): 
        help("Manage, build and interact with agents.")

        command("list"):
            help("List all agents.")

        command("build"):
            help("Build an agent to connect to an active listener.")


        command("interact"):
            help("Interact with an active agent.")


    command("help"):
        nohelpflag()

    command("exit"):
        nohelpflag()

proc handleConsoleCommand*(cq: Conquest, args: varargs[string]) = 

    # Return if no command (or just whitespace) is entered
    if args[0].replace(" ", "").len == 0: return

    let date: string = now().format("dd-MM-yyyy HH:mm:ss")
    cq.writeLine(fgCyan, fmt"[{date}] ", resetStyle, styleBright, args[0])

    try:
        let opts = parser.parse(args[0].split(" ").filterIt(it.len > 0))

        case opts.command
        
        of "exit": # Exit program 
            echo "\n"
            quit(0) 

        of "help": # Display help menu
            cq.writeLine(parser.help())

        of "listener": 
            case opts.listener.get.command
            of "list":
                cq.listenerList()
            of "start": 
                cq.listenerStart(opts.listener.get.start.get.host, opts.listener.get.start.get.port)
            of "stop": 
                cq.listenerStop(opts.listener.get.stop.get.name)
            else: 
                cq.listenerUsage()

        of "agent":
            case opts.agent.get.command
            of "list":
                cq.agentList()
            of "build": 
                cq.agentBuild()
            of "interact":
                cq.agentInteract() 
            else: 
                cq.agentUsage()

    # Handle help flag
    except ShortCircuit as err:
        if err.flag == "argparse_help":
            cq.writeLine(err.help)
    
    # Handle invalid arguments
    except UsageError: 
        cq.writeLine(fgRed, styleBright, "[-] ", getCurrentExceptionMsg())
    
    cq.writeLine("")

proc header(cq: Conquest) = 
    cq.writeLine("")
    cq.writeLine("┏┏┓┏┓┏┓┓┏┏┓┏╋")
    cq.writeLine("┗┗┛┛┗┗┫┗┻┗ ┛┗ V0.1")
    cq.writeLine("      ┗  @jakobfriedl")  
    cq.writeLine("─".repeat(21))
    cq.writeLine("")
    

#[
    Conquest framework entry point
]#
proc main() =

    # Handle CTRL+C,  
    proc exit() {.noconv.} = 
        echo "Received CTRL+C. Type \"exit\" to close the application.\n"    

    setControlCHook(exit)

    # Initialize framework
    cq = initConquest() 

    # Print header
    cq.header()
    
    # Initialize database
    cq.dbInit()
    cq.restartListeners()

    # Main loop
    while true: 
        cq.setIndicator("[conquest]> ")
        cq.setStatusBar(@[("mode", "manage"), ("listeners", $len(cq.listeners)), ("agents", $len(cq.agents))])    
        cq.showPrompt() 
            
        var command: string = cq.readLine()
        cq.withOutput(handleConsoleCommand, command)

when isMainModule:
    main()