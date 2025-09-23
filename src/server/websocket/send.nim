import times, tables
import ../../common/[types, utils, serialize]
import mummy

#[
    [ Sending functions ]
    Server -> Client
]#
proc sendHeartbeat*(ws: WebSocket) = 
    var packer = Packer.init() 

    packer.add(cast[uint8](CLIENT_HEARTBEAT))
    let data = packer.pack() 

    ws.send(Bytes.toString(data), BinaryMessage)

proc sendEventlogItem*(ws: WebSocket, logType: LogType, message: string, timestamp: int64 = now().toTime().toUnix()) = 
    var packer = Packer.init() 

    packer.add(cast[uint8](CLIENT_EVENT_LOG))
    packer.add(cast[uint8](logType))
    packer.add(cast[uint32](timestamp))
    packer.addDataWithLengthPrefix(string.toBytes(message))
    let data = packer.pack() 

    ws.send(Bytes.toString(data), BinaryMessage)

proc sendConsoleItem*(ws: WebSocket, agentId: string, logType: LogType, message: string, timestamp: int64 = now().toTime().toUnix()) = 
    var packer = Packer.init() 

    packer.add(cast[uint8](CLIENT_CONSOLE_LOG))
    packer.add(string.toUUid(agentId))
    packer.add(cast[uint8](logType))
    packer.add(cast[uint32](timestamp))
    packer.addDataWithLengthPrefix(string.toBytes(message))
    let data = packer.pack() 

    ws.send(Bytes.toString(data), BinaryMessage)

proc sendAgentCheckin*(ws: WebSocket, agentId: string, timestamp: int64) = 
    var packer = Packer.init() 

    packer.add(cast[uint8](CLIENT_AGENT_CHECKIN))
    packer.add(string.toUUid(agentId))
    packer.add(cast[uint32](timestamp))
    let data = packer.pack() 

    ws.send(Bytes.toString(data), BinaryMessage)

proc sendAgentPayload*(ws: WebSocket, payload: seq[byte]) = 
    var packer = Packer.init() 

    packer.add(cast[uint8](CLIENT_AGENT_BINARY))
    packer.addDataWithLengthPrefix(payload)
    let data = packer.pack() 

    ws.send(Bytes.toString(data), BinaryMessage)

proc sendAgentConnection*(ws: WebSocket, agent: Agent) = 
    var packer = Packer.init() 

    packer.add(cast[uint8](CLIENT_AGENT_CONNECTION))
    packer.add(string.toUuid(agent.agentId))
    packer.add(string.toUuid(agent.listenerId))
    packer.addDataWithLengthPrefix(string.toBytes(agent.username))
    packer.addDataWithLengthPrefix(string.toBytes(agent.hostname))
    packer.addDataWithLengthPrefix(string.toBytes(agent.domain))
    packer.addDataWithLengthPrefix(string.toBytes(agent.ip))
    packer.addDataWithLengthPrefix(string.toBytes(agent.os))
    packer.addDataWithLengthPrefix(string.toBytes(agent.process))
    packer.add(uint32(agent.pid))
    packer.add(uint8(agent.elevated))
    packer.add(uint32(agent.sleep))
    packer.add(cast[uint32](agent.firstCheckin))
    packer.add(cast[uint32](agent.latestCheckin))
    let data = packer.pack() 

    ws.send(Bytes.toString(data), BinaryMessage)

