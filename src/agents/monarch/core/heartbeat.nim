import times 

import ../../../common/[types, serialize, utils]

proc createHeartbeat*(config: AgentConfig): Heartbeat = 
    return Heartbeat(
        header: Header(
            magic: MAGIC,
            version: VERSION, 
            packetType: cast[uint8](MSG_HEARTBEAT),
            flags: cast[uint16](FLAG_PLAINTEXT),
            seqNr: 0'u32, # Sequence number is not used for heartbeats
            size: 0'u32,
            hmac: default(array[16, byte])
        ), 
        agentId: uuidToUint32(config.agentId),
        listenerId: uuidToUint32(config.listenerId),
        timestamp: uint32(now().toTime().toUnix())
    )

proc serializeHeartbeat*(request: Heartbeat): seq[byte] =

    var packer = initPacker()

    # Serialize check-in / heartbeat request
    packer 
        .add(request.agentId)
        .add(request.listenerId)
        .add(request.timestamp)

    let body = packer.pack()
    packer.reset()

    # TODO: Encrypt check-in / heartbeat request body 

    # Serialize header
    let header = packer.packHeader(request.header, uint32(body.len))

    return header & body