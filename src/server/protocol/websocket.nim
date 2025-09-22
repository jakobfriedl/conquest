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

proc sendEventlogItem*(ws: WebSocket, logType: LogType, timestamp: int64, message: string) = 
    var packer = Packer.init() 

    packer.add(cast[uint8](CLIENT_EVENT_LOG))
    packer.add(cast[uint8](logType))
    packer.add(cast[uint32](timestamp))
    packer.addDataWithLengthPrefix(string.toBytes(message))
    let data = packer.pack() 

    ws.send(Bytes.toString(data), BinaryMessage)

#[
    [ Retrieval functions ]
    Client -> Server
]#
proc getMessageType*(message: Message): WsMessageAction = 
    var unpacker = Unpacker.init(message.data)
    return cast[WsMessageAction](unpacker.getUint8()) 

proc receiveStartListener*(message: Message): Listener = 
    var unpacker = Unpacker.init(message.data)

    discard unpacker.getUint8() 

    return Listener(
        server: nil,
        listenerId: Uuid.toString(unpacker.getUint32()),
        address: unpacker.getDataWithLengthPrefix(),
        port: int(unpacker.getUint16()),
        protocol: cast[Protocol](unpacker.getUint8())
    )