import mummy
import times, tables, json, base64, parsetoml
import ../utils
import ../../common/[types, utils, serialize, event]
export sendHeartbeat

#[
    Server -> Client
]#
proc sendProfile*(ws: WebSocket, profile: Profile) = 
    let event = Event(
        eventType: CLIENT_PROFILE,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "profile": profile.toTomlString()
        }
    )
    ws.sendEvent(event)

proc sendEventlogItem*(ws: WebSocket, logType: LogType, message: string) = 
    let event = Event(
        eventType: CLIENT_EVENTLOG_ITEM,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "logType": cast[uint8](logType),
            "message": message
        }
    )
    ws.sendEvent(event)

proc sendAgent*(ws: WebSocket, agent: Agent) = 
    let event = Event(
        eventType: CLIENT_AGENT_ADD, 
        timestamp: now().toTime().toUnix(),
        data: %agent
    )
    ws.sendEvent(event)

proc sendListener*(ws: WebSocket, listener: Listener) =
    let event = Event(
        eventType: CLIENT_LISTENER_ADD,
        timestamp: now().toTime().toUnix(),
        data: %listener
    )
    ws.sendEvent(event)

proc sendAgentCheckin*(ws: WebSocket, agentId: string) = 
    let event = Event(
        eventType: CLIENT_AGENT_CHECKIN,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "agentId": agentId
        }
    )
    ws.sendEvent(event)

proc sendAgentPayload*(ws: WebSocket, agentId: string, bytes: seq[byte]) =
    let event = Event(
        eventType: CLIENT_AGENT_PAYLOAD, 
        timestamp: now().toTime().toUnix(),
        data: %*{
            "agentId": agentId,
            "payload": encode(bytes)
        }
    )
    ws.sendEvent(event)

proc sendConsoleItem*(ws: WebSocket, agentId: string, logType: LogType, message: string) = 
    let event = Event(
        eventType: CLIENT_CONSOLE_ITEM,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "agentId": agentId,
            "logType": cast[uint8](logType),
            "message": message
        }
    )
    ws.sendEvent(event)
