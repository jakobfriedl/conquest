import prompt, terminal, argparse, parsetoml
import strutils, strformat, system, tables

import ./[agent, listener, builder]
import ../[globals, utils]
import ../db/database
import ../core/logger
import ../../common/[types, crypto, profile]

#[
    Argument parsing
]# 
var parser = newParser: 
    help("Conquest Command & Control")
    nohelpflag()

    command("listener"):
        help("Manage, start and stop listeners.")

        command("list"): 
            help("List all active listeners.")
        command("start"): 
            help("Starts a new HTTP listener.")
            option("-i", "--ip", default=some("127.0.0.1"), help="IPv4 address to listen on.", required=false)
            option("-p", "--port", help="Port to listen on.", required=true)
            
            # TODO: Future features:
            # flag("--dns", help="Use the DNS protocol for C2 communication.")
            # flag("--doh", help="Use DNS over HTTPS for C2 communication.)
        command("stop"):
            help("Stop an active listener.")
            option("-n", "--name", help="Name of the listener.", required=true)
    
    command("agent"): 
        help("Manage, build and interact with agents.")

        command("list"):
            help("List all agents.")
            option("-l", "--listener", help="Name of the listener.")

        command("info"): 
            help("Display details for a specific agent.")
            option("-n", "--name", help="Name of the agent.", required=true)

        command("kill"):
            help("Terminate the connection of an active listener and remove it from the interface.")
            option("-n", "--name", help="Name of the agent.", required=true)
            # flag("--self-delete", help="Remove agent executable from target system.")

        command("interact"):
            help("Interact with an active agent.")
            option("-n", "--name", help="Name of the agent.", required=true)

        command("build"): 
            help("Generate a new agent to connect to an active listener.")
            option("-l", "--listener", help="Name of the listener.", required=true)
            option("-s", "--sleep", help="Sleep delay in seconds." )
            # option("-p", "--payload", help="Agent type.\n\t\t\t    ", default=some("monarch"), choices = @["monarch"],)

    command("help"):
        nohelpflag()

    command("exit"):
        nohelpflag()

proc handleConsoleCommand(cq: Conquest, args: string) = 

    # Return if no command (or just whitespace) is entered
    if args.replace(" ", "").len == 0: return

    cq.input(args)

    try:
        let opts = parser.parse(args.split(" ").filterIt(it.len > 0))

        case opts.command
        
        of "exit": # Exit program 
            echo "\n"
            quit(0) 

        of "help": # Display help menu
            cq.output(parser.help())

        of "listener": 
            case opts.listener.get.command
            of "list":
                cq.listenerList()
            of "start": 
                cq.listenerStart(opts.listener.get.start.get.ip, opts.listener.get.start.get.port)
            of "stop": 
                cq.listenerStop(opts.listener.get.stop.get.name)
            else: 
                cq.listenerUsage()

        of "agent":
            case opts.agent.get.command
            of "list":    
                cq.agentList(opts.agent.get.list.get.listener)
            of "info":
                cq.agentInfo(opts.agent.get.info.get.name)
            of "kill": 
                cq.agentKill(opts.agent.get.kill.get.name)
            of "interact":
                cq.agentInteract(opts.agent.get.interact.get.name) 
            of "build": 
                cq.agentBuild(opts.agent.get.build.get.listener, opts.agent.get.build.get.sleep)
            else: 
                cq.agentUsage()

    # Handle help flag
    except ShortCircuit as err:
        if err.flag == "argparse_help":
            cq.error(err.help)
    
    # Handle invalid arguments
    except CatchableError: 
        cq.error(getCurrentExceptionMsg())
    
    cq.output()

proc header() = 
    echo ""
    echo "┏┏┓┏┓┏┓┓┏┏┓┏╋"
    echo "┗┗┛┛┗┗┫┗┻┗ ┛┗ V0.1"
    echo "      ┗  @jakobfriedl"  
    echo "─".repeat(21) 
    echo ""

proc init*(T: type Conquest, profile: Profile): Conquest = 
    var cq = new Conquest
    cq.prompt = Prompt.init() 
    cq.listeners = initTable[string, Listener]()
    cq.agents = initTable[string, Agent]() 
    cq.interactAgent = nil 
    cq.profile = profile
    cq.keyPair = loadKeyPair(profile.getString("private_key_file"))
    cq.dbPath = profile.getString("database_file")
    return cq

proc startServer*(profilePath: string) =

    # Handle CTRL+C,  
    proc exit() {.noconv.} = 
        echo "Received CTRL+C. Type \"exit\" to close the application.\n"    
    setControlCHook(exit)

    header()
    
    try:
        # Initialize framework context
        # Load and parse profile 
        let profile = parseFile(profilePath)
        cq = Conquest.init(profile)

        cq.info("Using profile \"", profile.getString("name"), "\" (", profilePath ,").")
        cq.info("Using private key \"", profile.getString("private_key_file"), "\".")
        
    except CatchableError as err:
        echo err.msg
        quit(0)
    
    # Initialize database
    cq.dbInit()
    cq.restartListeners()
    cq.addMultiple(cq.dbGetAllAgents())

    # Main loop
    while true: 
        cq.prompt.setIndicator("[conquest]> ")
        cq.prompt.setStatusBar(@[("[mode]", "manage"), ("[listeners]", $len(cq.listeners)), ("[agents]", $len(cq.agents))])    
        cq.prompt.showPrompt() 
 
        var command: string = cq.prompt.readLine()
        cq.handleConsoleCommand(command)
