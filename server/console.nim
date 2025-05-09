import prompt, terminal
import argparse
import strutils, strformat, times, system, unicode

import ./[types, agent]
import listener/listener
import db/database

#[
    Argument parsing
]# 
var parser = newParser: 
    help("Console Command & Control")

    command("listener"):
        help("Manage, start and stop listeners.")

        command("list"): 
            help("List all active listeners.")
        command("start"): 
            help("Starts a new HTTP listener.")
            option("-h", "-host", default=some("0.0.0.0"), help="IPv4 address to listen on.", required=false)
            option("-p", "-port", help="Port to listen on.", required=true)
            # flag("--dns", help="Use the DNS protocol for C2 communication.")
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
            help("Interact with an active listener.")


    command("help"):
        nohelpflag()

    command("exit"):
        nohelpflag()

proc handleConsoleCommand*(console: Console, args: varargs[string]) = 

    # Return if no command (or just whitespace) is entered
    if args[0].replace(" ", "").len == 0: return

    let date: string = now().format("dd-MM-yyyy HH:mm:ss")
    console.writeLine(fgCyan, fmt"[{date}] ", resetStyle, styleBright, args[0])

    try:
        let opts = parser.parse(args[0].split(" ").filterIt(it.len > 0))

        case opts.command
        
        of "exit": # Exit program 
            echo "\n"
            quit(0) 

        of "help": # Display help menu
            console.writeLine(parser.help())

        of "listener": 
            case opts.listener.get.command
            of "list":
                console.listenerList()
            of "start": 
                console.listenerStart(opts.listener.get.start.get.host, opts.listener.get.start.get.port)
            of "stop": 
                console.listenerStop(opts.listener.get.stop.get.name)
            else: 
                console.listenerUsage()

        of "agent":
            case opts.agent.get.command
            of "list":
                console.agentList()
            of "build": 
                console.agentBuild()
            of "interact":
                console.agentInteract() 
            else: 
                console.listenerUsage()

    # Handle help flag
    except ShortCircuit as err:
        if err.flag == "argparse_help":
            console.writeLine(err.help)
    
    # Handle invalid arguments
    except UsageError: 
        console.writeLine(fgRed, styleBright, "[-] ", getCurrentExceptionMsg())
    
    console.writeLine("")

proc header(console: Console) = 
    console.writeLine("")
    console.writeLine("┏┏┓┏┓┏┓┓┏┏┓┏╋")
    console.writeLine("┗┗┛┛┗┗┫┗┻┗ ┛┗ 0.1")
    console.writeLine("      ┗  @jakobfriedl")  
    console.writeLine("─".repeat(21))
    console.writeLine("")
    
proc initPrompt*() =

    var console = newConsole()

    # Print header
    console.header()
    
    # Initialize database
    console.dbInit()
    console.restartListeners()

    # Main loop
    while true: 
        console.setIndicator("[conquest]> ")
        console.setStatusBar(@[("mode", "manage"), ("listeners", $console.listeners), ("agents", $console.agents)])    
        console.showPrompt() 
            
        var command: string = console.readLine()
        console.withOutput(handleConsoleCommand, command)

