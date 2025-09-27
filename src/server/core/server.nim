import prompt, terminal, argparse, parsetoml, times, json
import strutils, strformat, system, tables

import ./[agent, listener, builder]
import ../globals
import ../db/database
import ../core/logger
import ../../common/[types, crypto, utils, profile, event]
import ../websocket
import mummy, mummy/routers

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
            option("-s", "--sleep", help="Sleep delay in seconds.")
            option("--sleepmask", help="Sleep obfuscation technique.", default=some("none"), choices = @["ekko", "zilean", "foliage", "none"])
            flag("--spoof-stack", help="Use stack duplication to spoof the call stack. Supported by EKKO and ZILEAN techniques.")

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
                cq.listenerStart(generateUUID(), opts.listener.get.start.get.ip, parseInt(opts.listener.get.start.get.port), HTTP)
                discard
            of "stop": 
                cq.listenerStop(opts.listener.get.stop.get.name)
                discard
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
                cq.agentBuild(opts.agent.get.build.get.listener, opts.agent.get.build.get.sleep, opts.agent.get.build.get.sleepmask, opts.agent.get.build.get.spoof_stack)
            else: 
                cq.agentUsage()

    # Handle help flag
    except ShortCircuit as err:
        if err.flag == "argparse_help":
            cq.output(err.help)
    
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
    cq.threads = initTable[string, Thread[Listener]]()
    cq.agents = initTable[string, Agent]() 
    cq.interactAgent = nil 
    cq.profile = profile
    cq.keyPair = loadKeyPair(CONQUEST_ROOT & "/" & profile.getString("private-key-file"))
    cq.dbPath = CONQUEST_ROOT & "/" & profile.getString("database-file")
    cq.client = nil
    return cq

#[
    WebSocket
]#
proc upgradeHandler(request: Request) = 
    {.cast(gcsafe).}:
        let ws = request.upgradeToWebSocket()
        cq.client = UIClient(
            ws: ws
        )

proc websocketHandler(ws: WebSocket, event: WebSocketEvent, message: Message) {.gcsafe.} = 
    {.cast(gcsafe).}:
        case event:
        of OpenEvent:
            # New client connected to team server
            # Send profile, sessions and listeners to the UI client
            cq.client.sendProfile(cq.profile)
            for id, listener in cq.listeners: 
                cq.client.sendListener(listener)
            for id, agent in cq.agents: 
                cq.client.sendAgent(agent)
            cq.client.sendEventlogItem(LOG_SUCCESS_SHORT, "CQ-V1")
    
        of MessageEvent:
            # Continuously send heartbeat messages
            ws.sendHeartbeat() 

            let event = message.recvEvent()

            case event.eventType: 
            of CLIENT_AGENT_COMMAND:
                discard 

            of CLIENT_LISTENER_START:
                let listener = event.data.to(UIListener)
                cq.listenerStart(listener.listenerId, listener.address, listener.port, listener.protocol)
            
            of CLIENT_LISTENER_STOP:
                let listenerId = event.data["listenerId"].getStr()
                cq.listenerStop(listenerId)

            of CLIENT_AGENT_BUILD:
                discard 
            else: discard

        of ErrorEvent:
            discard 
        of CloseEvent:
            # Set the client instance to nil again to prevent debug error messages
            cq.client = nil
    
proc serve(server: Server) {.thread.} = 
    try:
        server.serve(Port(12345))
    except Exception:
        discard 

proc startServer*(profilePath: string) =

    # Ensure that the conquest root directory was passed as a compile-time define 
    when not defined(CONQUEST_ROOT): 
        quit(0)

    # Handle CTRL+C,  
    proc exit() {.noconv.} = 
        echo "Received CTRL+C. Type \"exit\" to close the application.\n"    
    setControlCHook(exit)

    header()
    
    try:
        # Initialize framework context
        # Load and parse profile 
        let profile = parsetoml.parseFile(profilePath)
        cq = Conquest.init(profile)

        cq.info("Using profile \"", profile.getString("name"), "\" (", profilePath ,").")
        
    except CatchableError as err:
        echo err.msg
        quit(0)
    
    # Initialize database
    cq.dbInit()
    cq.restartListeners()
    cq.addMultiple(cq.dbGetAllAgents())

    # Start websocket server
    var router: Router
    router.get("/*", upgradeHandler)
    let server = newServer(router, websocketHandler)
    
    var thread: Thread[Server]
    createThread(thread, serve, server)

    # Main loop
    while true: 
    
        cq.prompt.setIndicator("[conquest]> ")
        cq.prompt.setStatusBar(@[("[mode]", "manage"), ("[listeners]", $len(cq.listeners)), ("[agents]", $len(cq.agents))])    
        cq.prompt.showPrompt() 
 
        var command: string = cq.prompt.readLine()
        cq.handleConsoleCommand(command)
