import whisky 
import times, tables, json, base64
import ../../common/[types, utils, serialize, event]
export sendHeartbeat, recvEvent

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
        data: %*{
            "listenerId": buildInformation.listenerId, 
            "sleepDelay": buildInformation.sleepDelay,
            "sleepTechnique": cast[uint8](buildInformation.sleepTechnique),
            "spoofStack": buildInformation.spoofStack,
            "modules": buildInformation.modules
        }
    )
    connection.ws.sendEvent(event, connection.sessionKey)

proc sendAgentTask*(connection: WsConnection, agentId: string, command: string, task: Task) = 
    let event = Event(
        eventType: CLIENT_AGENT_TASK,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "agentId": agentId,
            "command": command,
            "task": task    
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