import whisky 
import times, tables, json
import ./views/[sessions, listeners, console, eventlog]
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

# proc sendAgentCommand*(ws: WebSocket, agentId: string, command: string) = 
#     var packer = Packer.init() 

#     packer.add(cast[uint8](CLIENT_AGENT_COMMAND))
#     packer.add(string.toUuid(agentId))
#     packer.addDataWithLengthPrefix(string.toBytes(command))
#     let data = packer.pack() 

#     ws.send(Bytes.toString(data), BinaryMessage)

# proc sendAgentBuild*(ws: WebSocket, listenerId: string, sleepDelay: int, sleepMask: SleepObfuscationTechnique, spoofStack: bool, modules: uint32) = 
#     var packer = Packer.init() 

#     packer.add(cast[uint8](CLIENT_AGENT_BUILD))
#     packer.add(string.toUuid(listenerId))
#     packer.add(cast[uint32](sleepDelay))
#     packer.add(cast[uint8](sleepMask))
#     packer.add(cast[uint8](spoofStack))
#     packer.add(modules)
#     let data = packer.pack() 

#     ws.send(Bytes.toString(data), BinaryMessage)
    