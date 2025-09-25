import times, tables
import ../globals
import ../../common/[types, utils, serialize]
import mummy
import ./send
import ../core/[task, listener]

#[
    [ Retrieval functions ]
    Client -> Server
]#
proc getMessageType*(message: Message): WsPacketType = 
    var unpacker = Unpacker.init(message.data)
    return cast[WsPacketType](unpacker.getUint8()) 

proc receiveStartListener*(message: Message) = 
    var unpacker = Unpacker.init(message.data)

    discard unpacker.getUint8() 
    let 
        listenerId = Uuid.toString(unpacker.getUint32())
        address = unpacker.getDataWithLengthPrefix()
        port = int(unpacker.getUint16())
        protocol = cast[Protocol](unpacker.getUint8())
    cq.ws.sendEventlogItem(LOG_INFO_SHORT, "Attempting to start listener.")
    cq.listenerStart(listenerId, address, port, protocol)

proc receiveStopListener*(message: Message) = 
    var unpacker = Unpacker.init(message.data)

    discard unpacker.getUint8() 
    let listenerId = Uuid.toString(unpacker.getUint32())
    cq.listenerStop(listenerId)

proc receiveAgentCommand*(message: Message) = 
    var unpacker = Unpacker.init(message.data)

    discard unpacker.getUint8() 
    let 
        agentId = Uuid.toString(unpacker.getUint32())
        command = unpacker.getDataWithLengthPrefix() 
    
