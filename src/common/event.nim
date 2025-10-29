when defined(server):
    import mummy
when defined(client): 
    import whisky

import times, json, zippy
import ./[types, utils, serialize, crypto]

proc sendEvent*(ws: WebSocket, event: Event, key: Key = default(Key)) = 
    var packer = Packer.init() 

    let iv = generateBytes(Iv)
    var data = string.toBytes($event.data)

    packer.add(cast[uint8](event.eventType))
    packer.add(cast[uint32](event.timestamp))
    
    if event.eventType != CLIENT_KEY_EXCHANGE and event.eventType != CLIENT_HEARTBEAT: 
        # Compress data
        let compressed = compress(data, BestCompression, dfGzip)
        
        # Encrypt data
        let (encData, gmac) = encrypt(key, iv, compressed)
        
        packer.addData(iv)      # 12 bytes IV
        packer.addData(gmac)    # 16 bytes Authentication Tag
        packer.addDataWithLengthPrefix(encData)
    else: 
        packer.addDataWithLengthPrefix(data)
    
    let body = packer.pack()

    ws.send(Bytes.toString(body), BinaryMessage)

proc recvEvent*(message: Message, key: Key = default(Key)): Event = 

    var unpacker = Unpacker.init(message.data)
    let 
        eventType = cast[EventType](unpacker.getUint8()) 
        timestamp = cast[int64](unpacker.getUint32())
    var data: string

    if eventType != CLIENT_KEY_EXCHANGE and eventType != CLIENT_HEARTBEAT: 
    
        let 
            iv = unpacker.getByteArray(Iv)
            gmac = unpacker.getByteArray(AuthenticationTag)
            encData = string.toBytes(unpacker.getDataWithLengthPrefix())
    
        # Decrypt data
        let (decData, tag) = decrypt(key, iv, encData)
        if tag != gmac: 
            raise newException(CatchableError, "Invalid authentication tag.")

        # Decompress data
        data = Bytes.toString(uncompress(decData, dfGzip))
    else: 
        data = unpacker.getDataWithLengthPrefix()

    return Event(
        eventType: eventType,
        timestamp: timestamp,
        data: parseJson(data)
    )

proc sendHeartbeat*(ws: WebSocket) = 
    let event = Event(
        eventType: CLIENT_HEARTBEAT,
        timestamp: now().toTime().toUnix(),
        data: %*{}
    )
    ws.sendEvent(event)