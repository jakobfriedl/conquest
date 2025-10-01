import times, json, base64, parsetoml
import ../common/[types, event]

export sendHeartbeat, recvEvent

proc `%`*(agent: Agent): JsonNode =
    result = newJObject()
    result["agentId"] = %agent.agentId
    result["listenerId"] = %agent.listenerId
    result["username"] = %agent.username
    result["hostname"] = %agent.hostname
    result["domain"] = %agent.domain
    result["ip"] = %agent.ip
    result["os"] = %agent.os
    result["process"] = %agent.process
    result["pid"] = %agent.pid
    result["elevated"] = %agent.elevated
    result["sleep"] = %agent.sleep
    result["firstCheckin"] = %agent.firstCheckin.toTime().toUnix()
    result["latestCheckin"] = %agent.latestCheckin.toTime().toUnix()

proc `%`*(listener: Listener): JsonNode =
    result = newJObject()
    result["listenerId"] = %listener.listenerId
    result["address"] = %listener.address
    result["port"] = %listener.port 
    result["protocol"] = %listener.protocol

#[
    Server -> Client
]#
proc sendProfile*(client: UIClient, profile: Profile) = 
    let event = Event(
        eventType: CLIENT_PROFILE,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "profile": profile.toTomlString()
        }
    )
    if client != nil: 
        client.ws.sendEvent(event)

proc sendEventlogItem*(client: UIClient, logType: LogType, message: string) = 
    let event = Event(
        eventType: CLIENT_EVENTLOG_ITEM,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "logType": cast[uint8](logType),
            "message": message
        }
    )
    if client != nil: 
        client.ws.sendEvent(event)

proc sendAgent*(client: UIClient, agent: Agent) = 
    let event = Event(
        eventType: CLIENT_AGENT_ADD, 
        timestamp: now().toTime().toUnix(),
        data: %agent
    )
    if client != nil: 
        client.ws.sendEvent(event)

proc sendListener*(client: UIClient, listener: Listener) =
    let event = Event(
        eventType: CLIENT_LISTENER_ADD,
        timestamp: now().toTime().toUnix(),
        data: %listener
    )
    if client != nil: 
        client.ws.sendEvent(event)

proc sendAgentCheckin*(client: UIClient, agentId: string) = 
    let event = Event(
        eventType: CLIENT_AGENT_CHECKIN,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "agentId": agentId
        }
    )
    if client != nil: 
        client.ws.sendEvent(event)

proc sendAgentPayload*(client: UIClient, bytes: seq[byte]) =
    let event = Event(
        eventType: CLIENT_AGENT_PAYLOAD, 
        timestamp: now().toTime().toUnix(),
        data: %*{
            "payload": encode(bytes)
        }
    )
    if client != nil: 
        client.ws.sendEvent(event)

proc sendConsoleItem*(client: UIClient, agentId: string, logType: LogType, message: string) = 
    let event = Event(
        eventType: CLIENT_CONSOLE_ITEM,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "agentId": agentId,
            "logType": cast[uint8](logType),
            "message": message
        }
    )
    if client != nil: 
        client.ws.sendEvent(event)
