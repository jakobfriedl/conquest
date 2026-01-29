import times, json, base64, strformat, tables
import stb_image/write as stbiw
import ./logger
import ../../common/[utils, event]
import ../../types/[common, server, event]
export recvEvent

proc `%`*(agent: Agent): JsonNode =
    result = newJObject()
    result["agentId"] = %agent.agentId
    result["listenerId"] = %agent.listenerId
    result["username"] = %agent.username
    result["impersonationToken"] = %agent.impersonationToken
    result["hostname"] = %agent.hostname
    result["domain"] = %agent.domain
    result["ipInternal"] = %agent.ipInternal
    result["ipExternal"] = %agent.ipExternal
    result["os"] = %agent.os
    result["process"] = %agent.process
    result["pid"] = %agent.pid
    result["elevated"] = %agent.elevated
    result["sleep"] = %agent.sleep
    result["jitter"] = %agent.jitter
    result["modules"] = %agent.modules
    result["firstCheckin"] = %agent.firstCheckin
    result["latestCheckin"] = %agent.latestCheckin

proc `%`*(listener: Listener): JsonNode =
    result = newJObject()
    result["listenerId"] = %listener.listenerId
    result["listenerType"] = %listener.listenerType
    
    case listener.listenerType:
    of LISTENER_HTTP:
        result["hosts"] = %listener.hosts
        result["address"] = %listener.address
        result["port"] = %listener.port 
    of LISTENER_SMB:
        result["pipe"] = %listener.pipe

proc broadcast(cq: Conquest, event: Event, clientId: string) =
    if clientId != "":
        if cq.clients.hasKey(clientId): 
            let client = cq.clients[clientId]
            client.ws.sendEvent(event, client.sessionKey)
    else:
        for id, client in cq.clients:
            client.ws.sendEvent(event, client.sessionKey)

#[
    Server -> Client
]#
proc sendPublicKey*(cq: Conquest, publicKey: Key, clientId: string = "") = 
    let event = Event(
        eventType: CLIENT_KEY_EXCHANGE,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "publicKey": encode(Bytes.toString(publicKey))
        }
    )
    cq.broadcast(event, clientId)

proc sendProfile*(cq: Conquest, profileString: string, clientId: string = "") = 
    let event = Event(
        eventType: CLIENT_PROFILE,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "profile": profileString
        }
    )
    cq.broadcast(event, clientId)

proc sendEventlogItem*(cq: Conquest, logType: LogType, message: string, clientId: string = "") = 
    let event = Event(
        eventType: CLIENT_EVENTLOG_ITEM,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "logType": cast[uint8](logType),
            "message": message
        }
    )

    # Log event 
    let timestamp = event.timestamp.fromUnix().local().format("dd-MM-yyyy HH:mm:ss")
    log(fmt"[{timestamp}]{$logType}{message}")

    if cq.clients.len > 0 or clientId != "":
        cq.broadcast(event, clientId)

proc sendConsoleItem*(cq: Conquest, agentId: string, logType: LogType, message: string, silent: bool = false, clientId: string = "") = 
    let event = Event(
        eventType: CLIENT_CONSOLE_ITEM,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "agentId": agentId,
            "logType": cast[uint8](logType),
            "message": message
        }
    )

    # Log console item
    let timestamp = event.timestamp.fromUnix().local().format("dd-MM-yyyy HH:mm:ss")
    if logType != LOG_OUTPUT: 
        log(fmt"[{timestamp}]{$logType}{message}", agentId)
    else: 
        log(message, agentId)

    if cq.clients.len > 0 or clientId != "":
        if not silent: 
            cq.broadcast(event, clientId)

proc sendAgent*(cq: Conquest, agent: Agent, clientId: string = "") = 
    let event = Event(
        eventType: CLIENT_AGENT_ADD, 
        timestamp: now().toTime().toUnix(),
        data: %agent
    )
    cq.broadcast(event, clientId)

proc sendListener*(cq: Conquest, listener: Listener, clientId: string = "") =
    let event = Event(
        eventType: CLIENT_LISTENER_ADD,
        timestamp: now().toTime().toUnix(),
        data: %listener
    )
    cq.broadcast(event, clientId)

proc sendListenerRemove*(cq: Conquest, listenerId: string, clientId: string = "") =
    let event = Event(
        eventType: CLIENT_LISTENER_REMOVE,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "listenerId": listenerId
        }
    )
    cq.broadcast(event, clientId)

proc sendAgentCheckin*(cq: Conquest, agentId: string, clientId: string = "") = 
    let event = Event(
        eventType: CLIENT_AGENT_CHECKIN,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "agentId": agentId
        }
    )
    cq.broadcast(event, clientId)

proc sendAgentPayload*(cq: Conquest, bytes: seq[byte], clientId: string = "") =
    let event = Event(
        eventType: CLIENT_AGENT_PAYLOAD, 
        timestamp: now().toTime().toUnix(),
        data: %*{
            "payload": encode(bytes)
        }
    )
    cq.broadcast(event, clientId)

proc sendBuildlogItem*(cq: Conquest, logType: LogType, message: string, clientId: string = "") = 
    let event = Event(
        eventType: CLIENT_BUILDLOG_ITEM,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "logType": cast[uint8](logType),
            "message": message
        }
    )
    cq.broadcast(event, clientId)

proc sendLoot*(cq: Conquest, loot: LootItem, clientId: string = "") = 
    let event = Event(
        eventType: CLIENT_LOOT_ADD,
        timestamp: now().toTime().toUnix(),
        data: %loot
    )
    cq.broadcast(event, clientId)

proc sendLootData*(cq: Conquest, loot: LootItem, data: string, clientId: string = "") = 
    let event = Event(
        eventType: CLIENT_LOOT_DATA,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "loot": %loot,
            "data": encode(data)
        }
    )
    cq.broadcast(event, clientId)

proc sendImpersonateToken*(cq: Conquest, agentId, username: string, clientId: string = "") = 
    let event = Event(
        eventType: CLIENT_IMPERSONATE_TOKEN,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "agentId": agentId,
            "username": username
        }
    )
    cq.broadcast(event, clientId)

proc sendRevertToken*(cq: Conquest, agentId: string, clientId: string = "") = 
    let event = Event(
        eventType: CLIENT_REVERT_TOKEN,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "agentId": agentId
        }
    )
    cq.broadcast(event, clientId)

proc sendProcessList*(cq: Conquest, agentId, procData: string, silent: bool, clientId: string = "") = 
    let event = Event(
        eventType: CLIENT_PROCESSES, 
        timestamp: now().toTime().toUnix(),
        data: %*{
            "agentId": agentId,
            "processes": procData,
            "silent": silent
        }
    )
    cq.broadcast(event, clientId)

proc sendDirectoryListing*(cq: Conquest, agentId, data: string, silent: bool, clientId: string = "") = 
    let event = Event(
        eventType: CLIENT_DIRECTORY_LISTING, 
        timestamp: now().toTime().toUnix(),
        data: %*{
            "agentId": agentId,
            "data": data,
            "silent": silent
        }
    )
    cq.broadcast(event, clientId)

proc sendWorkingDirectory*(cq: Conquest, agentId, directory: string, clientId: string = "") = 
    let event = Event(
        eventType: CLIENT_WORKING_DIRECTORY, 
        timestamp: now().toTime().toUnix(),
        data: %*{
            "agentId": agentId,
            "directory": directory
        }
    )
    cq.broadcast(event, clientId)