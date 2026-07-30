import times, zippy
import ../../../common/[serialize, utils, crypto]
import ../../../types/[common, agent, protocol]

proc createHeartbeat*(ctx: AgentCtx): Heartbeat = 
    return Heartbeat(
        header: Header(
            magic: MAGIC,
            version: VERSION, 
            packetType: MSG_HEARTBEAT.uint8,
            flags: FLAG_ENCRYPTED.uint16 or FLAG_COMPRESSED.uint16,
            size: 0'u32,
            agentId: string.toUuid(ctx.agentId),
            seqNr: 0'u32,  
            nonce: generateBytes(Nonce),
            mac: default(AuthenticationTag)
        ), 
        listenerId: string.toUuid(ctx.transport.listenerId),
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

    # Compress payload body
    let compressedPayload = compress(body, BestCompression, dfGzip)

    # Encrypt check-in / heartbeat request body 
    let (encData, mac) = encrypt(ctx.sessionKey, request.header.nonce, compressedPayload, request.header.seqNr)

    # Set authentication tag (MAC)
    request.header.mac = mac

    # Serialize header
    let header = packer.serializeHeader(request.header, uint32(encData.len))

    return header & encData