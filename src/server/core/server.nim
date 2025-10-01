import prompt, terminal, argparse, parsetoml, times, json, math
import strutils, strformat, system, tables

import ./[agent, listener, builder]
import ../globals
import ../db/database
import ../core/logger
import ../../common/[types, crypto, utils, profile, event]
import ../websocket
import mummy, mummy/routers

proc header() = 
    echo ""
    echo "┏┏┓┏┓┏┓┓┏┏┓┏╋"
    echo "┗┗┛┛┗┗┫┗┻┗ ┛┗ V0.1"
    echo "      ┗  @jakobfriedl"  
    echo "─".repeat(21) 
    echo ""

proc init*(T: type Conquest, profile: Profile): Conquest = 
    var cq = new Conquest
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
            of CLIENT_AGENT_TASK:
                let agentId = event.data["agentId"].getStr()
                let task = event.data["task"].to(Task) 
                cq.agents[agentId].tasks.add(task)

            of CLIENT_LISTENER_START:
                let listener = event.data.to(UIListener)
                cq.listenerStart(listener.listenerId, listener.address, listener.port, listener.protocol)
            
            of CLIENT_LISTENER_STOP:
                let listenerId = event.data["listenerId"].getStr()
                cq.listenerStop(listenerId)

            of CLIENT_AGENT_BUILD:
                let 
                    listenerId = event.data["listenerId"].getStr()
                    sleepDelay = event.data["sleepDelay"].getInt()
                    sleepTechnique = cast[SleepObfuscationTechnique](event.data["sleepTechnique"].getInt())
                    spoofStack = event.data["spoofStack"].getBool()
                    modules = cast[uint32](event.data["modules"].getInt())
                
                let payload = cq.agentBuild(listenerId, sleepDelay, sleepTechnique, spoofStack, modules)
                if payload.len() != 0: 
                    cq.client.sendAgentPayload(payload)

            else: discard

        of ErrorEvent:
            discard 
        of CloseEvent:
            # Set the client instance to nil again to prevent debug error messages
            cq.client = nil
    
proc startServer*(profilePath: string) =

    # Ensure that the conquest root directory was passed as a compile-time define 
    when not defined(CONQUEST_ROOT): 
        quit(0)

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
    for agent in cq.dbGetAllAgents():
        cq.agents[agent.agentId] = agent
    for listener in cq.dbGetAllListeners():
        cq.listeners[listener.listenerId] = listener

    # Restart existing listeners
    for listenerId, listener in cq.listeners: 
        cq.listenerStart(listenerId, listener.address, listener.port, listener.protocol)

    # Start websocket server
    var router: Router
    router.get("/*", upgradeHandler)
    
    # Increased websocket message length in order to support dotnet assembly execution
    let server = newServer(router, websocketHandler, maxMessageLen = 1024 * 1024 * 1024)
    server.serve(Port(cq.profile.getInt("team-server.port")), "0.0.0.0")