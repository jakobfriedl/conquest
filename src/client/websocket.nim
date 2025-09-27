import whisky 
import times, tables, json
import ../common/[types, utils, serialize, event]
export sendHeartbeat, recvEvent

#[
    Client -> Server 
]#
proc sendStartListener*(ws: WebSocket, listener: UIListener) = 
    let event = Event(
        eventType: CLIENT_LISTENER_START, 
        timestamp: now().toTime().toUnix(),
        data: %listener
    )
    ws.sendEvent(event)

proc sendStopListener*(ws: WebSocket, listenerId: string) = 
    let event = Event(
        eventType: CLIENT_LISTENER_STOP,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "listenerId": listenerId
        }
    )
    ws.sendEvent(event)

proc sendAgentBuild*(ws: WebSocket, buildInformation: AgentBuildInformation) = 
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
    ws.sendEvent(event)

proc sendAgentCommand*(ws: WebSocket, agentId: string, command: string) = 
    let event = Event(
        eventType: CLIENT_AGENT_COMMAND,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "agentId": agentId,
            "command": command    
        }
    )
    ws.sendEvent(event)
