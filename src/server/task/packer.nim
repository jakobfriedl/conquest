import strutils, strformat, streams, times
import ../utils
import ../../common/[types, utils, serialize]

proc serializeTask*(task: Task): seq[byte] = 

    var packer = initPacker() 

    # Serialize payload
    packer
        .add(task.taskId)
        .add(task.agentId)
        .add(task.listenerId)
        .add(task.timestamp)
        .add(task.command)
        .add(task.argCount)

    for arg in task.args:
        packer.addArgument(arg)

    let payload = packer.pack() 
    packer.reset()

    # TODO: Encrypt payload body

    # Serialize header 
    packer
        .add(task.header.magic)
        .add(task.header.version)
        .add(task.header.packetType)
        .add(task.header.flags)
        .add(task.header.seqNr) 
        .add(cast[uint32](payload.len))
        .addData(task.header.hmac)

    let header = packer.pack() 

    # TODO: Calculate and patch HMAC

    return header & payload

proc deserializeTaskResult*(resultData: seq[byte]): TaskResult = 

    var unpacker = initUnpacker(resultData.toString)

    let 
        magic = unpacker.getUint32()
        version = unpacker.getUint8()
        packetType = unpacker.getUint8()
        flags = unpacker.getUint16()
        seqNr = unpacker.getUint32()
        size = unpacker.getUint32()
        hmacBytes  = unpacker.getBytes(16) 

        # Explicit conversion from seq[byte] to array[16, byte]
    var hmac: array[16, byte]
    copyMem(hmac.addr, hmacBytes[0].unsafeAddr, 16)

    # Packet Validation
    if magic != MAGIC: 
        raise newException(CatchableError, "Invalid magic bytes.")

    # TODO: Validate sequence number 

    # TODO: Validate HMAC

    # TODO: Decrypt payload 
    # let payload = unpacker.getBytes(size)

    let 
        taskId = unpacker.getUint32()
        agentId = unpacker.getUint32()
        listenerId = unpacker.getUint32()
        timestamp = unpacker.getUint32()
        command = unpacker.getUint16()
        status = unpacker.getUint8()
        resultType = unpacker.getUint8()
        length = unpacker.getUint32()
        data = unpacker.getBytes(int(length))
    
    return TaskResult(
        header: Header(
            magic: magic,
            version: version,
            packetType: packetType, 
            flags: flags,
            seqNr: seqNr,
            size: size,
            hmac: hmac 
        ),
        taskId: taskId,
        agentId: agentId,
        listenerId: listenerId, 
        timestamp: timestamp,
        command: command,
        status: status,
        resultType: resultType,
        length: length,
        data: data
    )

proc deserializeNewAgent*(data: seq[byte]): Agent = 

    var unpacker = initUnpacker(data.toString)

    let 
        magic = unpacker.getUint32()
        version = unpacker.getUint8()
        packetType = unpacker.getUint8()
        flags = unpacker.getUint16()
        seqNr = unpacker.getUint32()
        size = unpacker.getUint32()
        hmacBytes  = unpacker.getBytes(16) 

    # Explicit conversion from seq[byte] to array[16, byte]
    var hmac: array[16, byte]
    copyMem(hmac.addr, hmacBytes[0].unsafeAddr, 16)

    # Packet Validation
    if magic != MAGIC: 
        raise newException(CatchableError, "Invalid magic bytes.")

    # TODO: Validate sequence number 

    # TODO: Validate HMAC

    # TODO: Decrypt payload 
    # let payload = unpacker.getBytes(size)

    let 
        agentId = unpacker.getUint32()
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
        agentId: uuidToString(agentId),
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
        jitter: 0.0,  # TODO: Remove jitter 
        tasks: @[],  
        firstCheckin: now(),
        latestCheckin: now()
    )


        
