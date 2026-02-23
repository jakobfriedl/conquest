import times, json, base64
import ../../common/[utils, event]
import ../../types/[common, client, event, protocol]
export recvEvent

#[
    Client -> Server 
]#
proc sendPublicKey*(connection: WsConnection, publicKey: Key) = 
    let event = Event(
        eventType: CLIENT_KEY_EXCHANGE,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "publicKey": encode(Bytes.toString(publicKey))
        }
    )
    connection.ws.sendEvent(event, connection.sessionKey)

proc sendAuthentication*(connection: WsConnection, username, password: string) = 
    let event = Event(
        eventType: CLIENT_AUTH,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "username": username,
            "password": password
        }
    )
    connection.ws.sendEvent(event, connection.sessionKey)

proc sendSyncRequest*(connection: WsConnection) = 
    let event = Event(
        eventType: CLIENT_SYNC,
        timestamp: now().toTime().toUnix(),
        data: %*{}
    )
    connection.ws.sendEvent(event, connection.sessionKey)

proc sendStartListener*(connection: WsConnection, listener: UIListener) = 
    let event = Event(
        eventType: CLIENT_LISTENER_START, 
        timestamp: now().toTime().toUnix(),
        data: %listener
    )
    connection.ws.sendEvent(event, connection.sessionKey)

proc sendStopListener*(connection: WsConnection, listenerId: string) = 
    let event = Event(
        eventType: CLIENT_LISTENER_STOP,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "listenerId": listenerId
        }
    )
    connection.ws.sendEvent(event, connection.sessionKey)

proc sendAgentBuild*(connection: WsConnection, buildInformation: AgentBuildInformation) = 
    let event = Event(
        eventType: CLIENT_AGENT_BUILD,
        timestamp: now().toTime().toUnix(), 
        data: %buildInformation
    )
    connection.ws.sendEvent(event, connection.sessionKey)

proc sendAgentTask*(connection: WsConnection, agentId: string, task: Task, command, message: string) = 
    let event = Event(
        eventType: CLIENT_AGENT_TASK,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "agentId": agentId,
            "task": task,
            "command": command,
            "message": message
        }
    )
    connection.ws.sendEvent(event, connection.sessionKey)

proc sendAgentRemove*(connection: WsConnection, agentId: string) = 
    let event = Event(
        eventType: CLIENT_AGENT_REMOVE, 
        timestamp: now().toTime().toUnix(),
        data: %*{
            "agentId": agentId
        }
    )
    connection.ws.sendEvent(event, connection.sessionKey)

proc sendRemoveLoot*(connection: WsConnection, lootId: string) = 
    let event = Event(
        eventType: CLIENT_LOOT_REMOVE, 
        timestamp: now().toTime().toUnix(),
        data: %*{
            "lootId": lootId
        }
    )
    connection.ws.sendEvent(event, connection.sessionKey)

proc sendGetLoot*(connection: WsConnection, lootId: string) = 
    let event = Event(
        eventType: CLIENT_LOOT_GET, 
        timestamp: now().toTime().toUnix(),
        data: %*{
            "lootId": lootId
        }
    )
    connection.ws.sendEvent(event, connection.sessionKey)

proc sendLog*(connection: WsConnection, agentId, message: string) = 
    let event = Event(
        eventType: CLIENT_LOG, 
        timestamp: now().toTime().toUnix(),
        data: %*{
            "agentId": agentId,
            "message": message
        }
    )
    connection.ws.sendEvent(event, connection.sessionKey)

proc sendChatMessage*(connection: WsConnection, message: string) = 
    let event = Event(
        eventType: CLIENT_CHAT, 
        timestamp: now().toTime().toUnix(),
        data: %*{
            "user": connection.user,
            "message": message
        }
    )
    connection.ws.sendEvent(event, connection.sessionKey)