import mummy, mummy/routers
import terminal, json, math, base64, times
import strutils, strformat, system, tables

import ./globals
import ./db/database
import ./core/[listener, logger, builder, websocket, auth]
import ../common/[crypto, utils, profile, event]
import ../types/[common, event, protocol, server]

proc header() = 
    echo ""
    echo "┏┏┓┏┓┏┓┓┏┏┓┏╋"
    echo "┗┗┛┛┗┗┫┗┻┗ ┛┗ V0.1"
    echo "      ┗  @jakobfriedl"  
    echo "─".repeat(21) 
    echo ""

proc init*(T: type Conquest, profileString: string): Conquest = 
    var cq = new Conquest
    cq.listeners = initTable[string, Listener]()
    cq.threads = initTable[string, Thread[Listener]]()
    cq.agents = initTable[string, Agent]() 
    cq.profileString = profileString
    cq.profile = parseString(profileString)
    cq.keyPair = loadKeyPair(CONQUEST_ROOT & "/" & cq.profile.getString("private-key-file"))
    cq.dbPath = CONQUEST_ROOT & "/" & cq.profile.getString("database-file")
    cq.clients = initTable[string, WsConnection]() 
    return cq

#[
    WebSocket
]#
proc upgradeHandler(request: Request) = 
    {.cast(gcsafe).}:
        let ws = request.upgradeToWebSocket()
        let clientId = generateUuid()
        cq.clients[clientId] = WsConnection(
            clientId: clientId,
            ws: ws
        )

proc websocketHandler(ws: WebSocket, event: WebSocketEvent, message: Message) {.gcsafe.} = 
    {.cast(gcsafe).}:
        
        # Get requesting clientId
        var clientId: string = ""
        for id, conn in cq.clients: 
            if conn.ws == ws: 
                clientId = conn.clientId
                break

        case event:
        of OpenEvent:
            # New client connected to team server
            # Send the public key for the key exchange, all other information with be transmitted when the key exchange is completed
            cq.sendPublicKey(cq.keyPair.publicKey, clientId = clientId)
    
        of MessageEvent:            
            let event = message.recvEvent(cq.clients[clientId].sessionKey)
            case event.eventType: 
            of CLIENT_KEY_EXCHANGE: 
                let publicKey = decode(event.data["publicKey"].getStr()).toKey()
                cq.clients[clientId].sessionKey = deriveSessionKey(cq.keyPair, publicKey)
            
            of CLIENT_AUTH:
                let username = event.data["username"].getStr()
                let password = event.data["password"].getStr()

                # Authenticate user 
                let auth = cq.authenticate(username, password)
                cq.sendAuthenticationResult(auth, clientId = clientId)

                # Send relevant information to the client if authentication succeeds
                if auth: 
                    # C2 profile 
                    cq.sendProfile(cq.profileString, clientId = clientId)
                    
                    # Listeners
                    for id, listener in cq.listeners: 
                        cq.sendListener(listener, clientId = clientId)
                    
                    # Agent sessions
                    for id, agent in cq.agents: 
                        cq.sendAgent(agent, clientId = clientId)

                    # Downloads & Screenshots metadata
                    for lootItem in cq.dbGetLoot():
                        cq.sendLoot(lootItem, clientId = clientId)

                    cq.clients[clientId].user = username
                    cq.sendEventlogItem(LOG_SUCCESS_SHORT, fmt"{username} connected.")

            of CLIENT_AGENT_TASK:
                let 
                    agentId = event.data["agentId"].getStr()
                    task = event.data["task"].to(Task) 
                    message = event.data["message"].getStr()
                
                cq.agents[agentId].tasks.add(task)
                log(message, agentId)

            of CLIENT_LISTENER_START:
                let listener = event.data.to(UIListener)
                cq.listenerStart(listener)
            
            of CLIENT_LISTENER_STOP:
                let listenerId = event.data["listenerId"].getStr()
                cq.listenerStop(listenerId)

            of CLIENT_AGENT_BUILD:
                let agentBuildInformation = event.data.to(AgentBuildInformation)
                let payload = cq.agentBuild(agentBuildInformation, clientId = clientId)
                if payload.len() != 0: 
                    cq.sendAgentPayload(payload, clientId = clientId)

            of CLIENT_AGENT_REMOVE: 
                let agentId = event.data["agentId"].getStr()
                discard cq.dbDeleteAgentByName(agentId)
                cq.agents.del(agentId)

            of CLIENT_LOOT_REMOVE: 
                if not cq.dbDeleteLootById(event.data["lootId"].getStr()): 
                    cq.sendEventlogItem(LOG_ERROR, "Failed to delete loot.")

            of CLIENT_LOOT_GET: 
                let loot = cq.dbGetLootById(event.data["lootId"].getStr())
                cq.sendLootData(loot, readFile(loot.path), clientId = clientId)

            of CLIENT_LOG: 
                log(event.data["message"].getStr(), event.data["agentId"].getStr())

            else: discard

        of ErrorEvent:
            discard 
            
        of CloseEvent:
            let user = cq.clients[clientId].user
            cq.clients.del(clientId)
            cq.sendEventlogItem(LOG_ERROR_SHORT, fmt"{user} disconnected.")

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
        let profileString = readFile(profilePath)
        cq = Conquest.init(profileString)

        cq.info("Using profile \"", cq.profile.getString("name"), "\" (", profilePath ,").")
        
        # Initialize database
        cq.dbInit()
        for agent in cq.dbGetAllAgents():
            cq.agents[agent.agentId] = agent
        for listener in cq.dbGetAllListeners():
            # Restart existing listeners
            cq.listenerStart(listener)

        # Start websocket server
        var router: Router
        router.get("/*", upgradeHandler)
        
        # Increased websocket message length in order to support dotnet assembly execution (1GB)
        let server = newServer(router, websocketHandler, maxBodyLen = 1024 * 1024 * 1024, maxMessageLen = 1024 * 1024 * 1024)
        server.serve(Port(cq.profile.getInt("team-server.port")), cq.profile.getString("team-server.host"))

    except CatchableError as err:
        echo err.msg
        quit(0)
    

# Conquest framework entry point
when isMainModule:
    import cligen; dispatch startServer