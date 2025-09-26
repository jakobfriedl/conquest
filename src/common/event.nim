when defined(server):
    import mummy
when defined(client): 
    import whisky

import times, json
import ./[types, utils, serialize]

proc sendEvent*(ws: WebSocket, event: Event) = 
    var packer = Packer.init() 

    packer.add(cast[uint8](event.eventType))
    packer.add(cast[uint32](event.timestamp))
    packer.addDataWithLengthPrefix(string.toBytes($event.data))
    let data = packer.pack() 

    ws.send(Bytes.toString(data), BinaryMessage)

proc recvEvent*(message: Message): Event = 
    var unpacker = Unpacker.init(message.data)

    return Event(
        eventType: cast[EventType](unpacker.getUint8()),
        timestamp: cast[int64](unpacker.getUint32()),
        data: parseJson(unpacker.getDataWithLengthPrefix())
    )

proc sendHeartbeat*(ws: WebSocket) = 
    let event = Event(
        eventType: CLIENT_HEARTBEAT,
        timestamp: now().toTime().toUnix(),
        data: %*{}
    )
    ws.sendEvent(event)