import times, tables
import ../common/[types, utils, serialize]
import views/[sessions, listeners, console, eventlog]
import whisky 

#[
    [ Sending Functions ]
    Client -> Server 
    - Heartbeat 
    - ListenerStart
    - ListenerStop
    - AgentBuild
    - AgentCommand
]#
proc sendHeartbeat*(ws: WebSocket) = 
    var packer = Packer.init() 

    packer.add(cast[uint8](CLIENT_HEARTBEAT))
    let data = packer.pack() 

    ws.send(Bytes.toString(data), BinaryMessage)

proc sendStartListener*(ws: WebSocket, listener: Listener) = 
    var packer = Packer.init() 

    packer.add(cast[uint8](CLIENT_LISTENER_START))
    packer.add(string.toUUid(listener.listenerId))
    packer.addDataWithLengthPrefix(string.toBytes(listener.address))
    packer.add(cast[uint16](listener.port))
    packer.add(cast[uint8](listener.protocol))

    let data = packer.pack() 

    ws.send(Bytes.toString(data), BinaryMessage)

proc sendStopListener*(ws: WebSocket, listenerId: string) = 
    var packer = Packer.init() 

    packer.add(cast[uint8](CLIENT_LISTENER_STOP))
    packer.add(string.toUuid(listenerId))
    let data = packer.pack() 

    ws.send(Bytes.toString(data), BinaryMessage)

proc sendAgentCommand*(ws: WebSocket, agentId: string, command: string) = 
    var packer = Packer.init() 

    packer.add(cast[uint8](CLIENT_AGENT_COMMAND))
    packer.add(string.toUuid(agentId))
    packer.addDataWithLengthPrefix(string.toBytes(command))
    let data = packer.pack() 

    ws.send(Bytes.toString(data), BinaryMessage)

proc sendAgentBuild*(ws: WebSocket, listenerId: string, sleepDelay: int, sleepMask: SleepObfuscationTechnique, spoofStack: bool, modules: uint32) = 
    var packer = Packer.init() 

    packer.add(cast[uint8](CLIENT_AGENT_BUILD))
    packer.add(string.toUuid(listenerId))
    packer.add(cast[uint32](sleepDelay))
    packer.add(cast[uint8](sleepMask))
    packer.add(cast[uint8](spoofStack))
    packer.add(modules)
    let data = packer.pack() 

    ws.send(Bytes.toString(data), BinaryMessage)
    
#[ 
    [ Retrieval Functions ]
    Server -> Client 
]#
proc getMessageType*(message: Message): WsMessageAction = 
    var unpacker = Unpacker.init(message.data)
    return cast[WsMessageAction](unpacker.getUint8()) 

proc receiveAgentPayload*(message: Message): seq[byte] = 
    var unpacker = Unpacker.init(message.data)
    
    discard unpacker.getUint8() 
    return string.toBytes(unpacker.getDataWithLengthPrefix())

proc receiveAgentConnection*(message: Message, sessions: ptr SessionsTableComponent) = 
    var unpacker = Unpacker.init(message.data)

    discard unpacker.getUint8() 
    let agent = Agent(
        agentId: Uuid.toString(unpacker.getUint32()),
        listenerId: Uuid.toString(unpacker.getUint32()),
        username: unpacker.getDataWithLengthPrefix(), 
        hostname: unpacker.getDataWithLengthPrefix(),
        domain: unpacker.getDataWithLengthPrefix(),
        ip: unpacker.getDataWithLengthPrefix(),
        os: unpacker.getDataWithLengthPrefix(),
        process: unpacker.getDataWithLengthPrefix(),
        pid: int(unpacker.getUint32()),
        elevated: unpacker.getUint8() != 0,
        sleep: int(unpacker.getUint32()),
        tasks: @[],  
        firstCheckin: cast[int64](unpacker.getUint32()).fromUnix().utc(),
        latestCheckin: cast[int64](unpacker.getUint32()).fromUnix().utc(),
    )

    sessions.agents.add(agent)

proc receiveAgentCheckin*(message: Message, sessions: ptr SessionsTableComponent)= 
    var unpacker = Unpacker.init(message.data)

    discard unpacker.getUint8() 
    let agentId = Uuid.toString(unpacker.getUint32())
    let timestamp = cast[int64](unpacker.getUint32())

    # TODO: Update checkin 

proc receiveConsoleItem*(message: Message, consoles: ptr Table[string, ConsoleComponent]) = 
    var unpacker = Unpacker.init(message.data)

    discard unpacker.getUint8() 
    let 
        agentId = Uuid.toString(unpacker.getUint32())
        logType = cast[LogType](unpacker.getUint8())
        timestamp = cast[int64](unpacker.getUint32())
        message = unpacker.getDataWithLengthPrefix()

    consoles[][agentId].addItem(logType, message, timestamp)

proc receiveEventlogItem*(message: Message, eventlog: ptr EventlogComponent) = 
    var unpacker = Unpacker.init(message.data)

    discard unpacker.getUint8() 
    let 
        logType = cast[LogType](unpacker.getUint8())
        timestamp = cast[int64](unpacker.getUint32())
        message = unpacker.getDataWithLengthPrefix()
    
    eventlog[].addItem(logType, message, timestamp)