import strutils, strformat

import ../types
import ../utils
import ../../../common/types
import ../../../common/serialize

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
    var args = newSeq[TaskArg](argCount) 

    # Parse arguments
    while argCount > 0: 
        args.add(unpacker.getArgument())
        dec argCount

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