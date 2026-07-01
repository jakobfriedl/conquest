import times, json, base64, strformat, tables, posix
import stb_image/write as stbiw
import ./logger
import ../db/database
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
    result["modules"] = %agent.modules
    result["firstCheckin"] = %agent.firstCheckin
    result["latestCheckin"] = %agent.latestCheckin

proc `%`*(listener: Listener): JsonNode =
    result = newJObject()
    result["listenerId"] = %listener.listenerId
    result["name"] = %listener.name
    result["listenerType"] = %listener.listenerType
    result["timestamp"] = %listener.timestamp
    
    case listener.listenerType:
    of LISTENER_HTTP:
        result["hosts"] = %listener.hosts
        result["address"] = %listener.address
        result["port"] = %listener.port 
        result["profile"] = %listener.profile
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
proc sendPublicKey*(cq: Conquest, publicKey: common.Key, clientId: string = "") = 
    let event = Event(
        eventType: CLIENT_KEY_EXCHANGE,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "publicKey": encode(Bytes.toString(publicKey))
        }
    )
    cq.broadcast(event, clientId)

proc sendAuthenticationResult*(cq: Conquest, success: bool, clientId: string = "") = 
    let event = Event(
        eventType: CLIENT_AUTH_RESULT,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "success": success
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

type Ifaddrs {.importc: "struct ifaddrs", header: "<ifaddrs.h>".} = object
    ifa_next {.importc.}: ptr Ifaddrs
    ifa_addr {.importc.}: ptr SockAddr

proc getifaddrs(pIfAddrs: var ptr Ifaddrs): cint {.importc, header: "<ifaddrs.h>".}
proc freeifaddrs(pIfAddrs: ptr Ifaddrs) {.importc, header: "<ifaddrs.h>".}

proc sendInterfaces*(cq: Conquest, clientId: string = "") =
    var addresses = @["0.0.0.0"]
    var pIfAddrs: ptr Ifaddrs
    if getifaddrs(pIfAddrs) == 0:
        defer: freeifaddrs(pIfAddrs)
        var curr = pIfAddrs
        while curr != nil:
            if curr.ifa_addr != nil and curr.ifa_addr.sa_family == TSa_Family(AF_INET):
                let b = cast[ptr array[4, uint8]](addr cast[ptr Sockaddr_in](curr.ifa_addr).sin_addr)
                let ip = fmt"{b[0]}.{b[1]}.{b[2]}.{b[3]}"
                if ip notin addresses:
                    addresses.add(ip)
            curr = curr.ifa_next

    let event = Event(
        eventType: CLIENT_INTERFACES,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "interfaces": addresses
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

proc sendConsoleItem*(cq: Conquest, agentId: string, logType: LogType, message: string, command: string = "", taskId: string = "", noOutput: bool = false, clientId: string = "") = 
    let event = Event(
        eventType: CLIENT_CONSOLE_ITEM,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "agentId": agentId,
            "logType": cast[uint8](logType),
            "command": command,
            "taskId": taskId,
            "message": message,
            "noOutput": noOutput
        }
    )

    # Log console item
    let timestamp = event.timestamp.fromUnix().local().format("dd-MM-yyyy HH:mm:ss")
    if logType != LOG_OUTPUT: 
        log(fmt"[{timestamp}]{$logType}{message}", agentId)
    else: 
        log(message, agentId)

    if cq.clients.len > 0 or clientId != "":
        cq.broadcast(event, clientId)

proc sendAgent*(cq: Conquest, agent: Agent, clientId: string = "") =
    let data = %agent
    data["parentId"] = %cq.dbGetParentAgent(agent.agentId) # Retrieve parent agent for session graph
    
    let event = Event(
        eventType: CLIENT_AGENT_ADD,
        timestamp: now().toTime().toUnix(),
        data: data
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

proc sendAgentPayload*(cq: Conquest, name: string, payload: seq[byte], clientId: string = "") =
    let event = Event(
        eventType: CLIENT_AGENT_PAYLOAD, 
        timestamp: now().toTime().toUnix(),
        data: %*{
            "name": name,
            "payload": encode(payload)
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

proc sendImpersonationToken*(cq: Conquest, agentId, impersonationToken: string, clientId: string = "") = 
    let event = Event(
        eventType: CLIENT_IMPERSONATE_TOKEN,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "agentId": agentId,
            "impersonationToken": impersonationToken
        }
    )
    cq.broadcast(event, clientId)

proc sendProcessList*(cq: Conquest, agentId, procData: string, clientId: string = "") = 
    let event = Event(
        eventType: CLIENT_PROCESSES, 
        timestamp: now().toTime().toUnix(),
        data: %*{
            "agentId": agentId,
            "processes": procData,
        }
    )
    cq.broadcast(event, clientId)

proc sendDirectoryListing*(cq: Conquest, agentId, data: string, clientId: string = "") = 
    let event = Event(
        eventType: CLIENT_DIRECTORY_LISTING, 
        timestamp: now().toTime().toUnix(),
        data: %*{
            "agentId": agentId,
            "data": data,
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

proc sendChatMessage*(cq: Conquest, user, message: string, clientId: string = "") = 
    let event = Event(
        eventType: CLIENT_CHAT, 
        timestamp: now().toTime().toUnix(),
        data: %*{
            "user": user,
            "message": message
        }
    )
    cq.broadcast(event, clientId)

proc sendJobs*(cq: Conquest, agentId, jobData: string, clientId: string = "") = 
    # Include table with the display names of the jobs in the request, so the client can label running jobs correctly
    var commands = newJObject()
    for taskId, cmd in cq.agents[agentId].taskCommands:
        commands[Uuid.toString(taskId)] = %cmd 
    
    let event = Event(
        eventType: CLIENT_JOBS, 
        timestamp: now().toTime().toUnix(),
        data: %*{
            "agentId": agentId,
            "jobs": jobData,
            "commands": commands,
        }
    )
    cq.broadcast(event, clientId)

proc sendLinks*(cq: Conquest, agentId, linkData: string, clientId: string = "") =
    let event = Event(
        eventType: CLIENT_LINKS, 
        timestamp: now().toTime().toUnix(),
        data: %*{
            "agentId": agentId,
            "links": linkData,
        }
    )
    cq.broadcast(event, clientId)

proc sendConfig*(cq: Conquest, agentId, agentConfig: string, clientId: string = "") =
    let event = Event(
        eventType: CLIENT_CONFIG, 
        timestamp: now().toTime().toUnix(),
        data: %*{
            "agentId": agentId,
            "config": agentConfig,
        }
    )
    cq.broadcast(event, clientId)

proc sendUpdateParent*(cq: Conquest, agentId, parentId: string, clientId: string = "") = 
    let event = Event(
        eventType: CLIENT_UPDATE_PARENT, 
        timestamp: now().toTime().toUnix(),
        data: %*{
            "agentId": agentId,
            "parentId": parentId
        }
    )
    cq.broadcast(event, clientId)

