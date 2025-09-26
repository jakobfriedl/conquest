import mummy
import times, tables, json, base64, parsetoml
import ../utils
import ../../common/[types, utils, serialize, event]
export sendHeartbeat

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

proc sendAgentPayload*(client: UIClient, agentId: string, bytes: seq[byte]) =
    let event = Event(
        eventType: CLIENT_AGENT_PAYLOAD, 
        timestamp: now().toTime().toUnix(),
        data: %*{
            "agentId": agentId,
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
