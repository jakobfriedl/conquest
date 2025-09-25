import whisky 
import times, tables
import ../views/[sessions, listeners, console, eventlog]
import ../../common/[types, utils, serialize, event]
export sendHeartbeat

#[
    Client -> Server 
]#
proc sendStartListener*(ws: WebSocket, listener: UIListener) = 
    var packer = Packer.init() 

    packer.add(cast[uint8](CLIENT_LISTENER_START))
    packer.add(string.toUUid(listener.listenerId))
    packer.addDataWithLengthPrefix(string.toBytes(listener.address))
    packer.add(cast[uint16](listener.port))
    packer.add(cast[uint8](listener.protocol))

    let data = packer.pack() 

    ws.send(Bytes.toString(data), BinaryMessage)

proc sendStopListener*(ws: WebSocket, listenerId: string) = 
    discard
    # var packer = Packer.init() 

    # packer.add(cast[uint8](CLIENT_LISTENER_STOP))
    # packer.add(string.toUuid(listenerId))
    # let data = packer.pack() 

    # ws.send(Bytes.toString(data), BinaryMessage)

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
    