import strutils, strformat

import ../[agentTypes, utils]
import ../../../common/[types, serialize]

proc deserializeTask*(bytes: seq[byte]): Task = 

    var unpacker = initUnpacker(bytes.toString)

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
    
    var argCount = unpacker.getUint8()
    var args = newSeq[TaskArg]() 

    # Parse arguments
    var i = 0
    while i < int(argCount): 
        args.add(unpacker.getArgument())
        inc i

    return Task(
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
        argCount: argCount,
        args: args
    )

proc deserializePacket*(packet: string): seq[Task] = 

    result = newSeq[Task]()

    var unpacker = initUnpacker(packet) 

    var taskCount = unpacker.getUint8()
    echo fmt"[*] Response contained {taskCount} tasks."
    if taskCount <= 0: 
        return @[]

    while taskCount > 0: 

        # Read length of each task and store the task object in a seq[byte]
        let 
            taskLength = unpacker.getUint32() 
            taskBytes = unpacker.getBytes(int(taskLength))

        result.add(deserializeTask(taskBytes))
        
        dec taskCount

proc serializeTaskResult*(taskResult: TaskResult): seq[byte] = 
    
    var packer = initPacker()

    # Serialize result body
    packer 
        .add(taskResult.taskId)
        .add(taskResult.agentId)
        .add(taskResult.listenerId)
        .add(taskResult.timestamp)
        .add(taskResult.command)
        .add(taskResult.status)
        .add(taskResult.resultType)
        .add(taskResult.length)

    if cast[ResultType](taskResult.resultType) != RESULT_NO_OUTPUT:
        packer.addData(taskResult.data)

    let body = packer.pack()
    packer.reset()

    # TODO: Encrypt result body 

    # Serialize header 
    packer
        .add(taskResult.header.magic)
        .add(taskResult.header.version)
        .add(taskResult.header.packetType)
        .add(taskResult.header.flags)
        .add(taskResult.header.seqNr) 
        .add(cast[uint32](body.len))
        .addData(taskResult.header.hmac)

    let header = packer.pack()

    # TODO: Calculate and patch HMAC

    return header & body 




