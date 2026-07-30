import times, zippy
import ../../../common/[serialize, sequence, crypto, utils]
import ../../../types/[common, agent, protocol]

proc createTaskResult*(ctx: AgentCtx, task: Task, status: StatusType, resultType: ResultType, resultData: seq[byte]): TaskResult =     
    return TaskResult(
        header: Header(
            magic: MAGIC,
            version: VERSION, 
            packetType: MSG_RESULT.uint8,
            flags: task.header.flags,       # Result packet has the same flags as the corresponding task
            size: 0'u32,
            agentId: string.toUuid(ctx.agentId),
            seqNr: nextSequence(string.toUuid(ctx.agentId)), 
            nonce: generateBytes(Nonce),
            mac: default(array[16, byte])
        ), 
        taskId: task.taskId,
        listenerId: string.toUuid(ctx.transport.listenerId),
        timestamp: uint32(now().toTime().toUnix()),
        command: task.command,
        status: cast[uint8](status),
        resultType: cast[uint8](resultType),
        length: uint32(resultData.len),
        data: resultData,
    )

proc serializeTaskResult*(ctx: AgentCtx, taskResult: var TaskResult): seq[byte] = 
    
    var packer = Packer.init()

    # Serialize result body
    packer 
        .add(taskResult.taskId)
        .add(taskResult.listenerId)
        .add(taskResult.timestamp)
        .add(taskResult.command)
        .add(taskResult.status)
        .add(taskResult.resultType)
        .addDataWithLengthPrefix(taskResult.data)

    var payload = packer.pack()
    packer.reset()

    # Compress payload 
    if (taskResult.header.flags and FLAG_COMPRESSED.uint16) != 0: 
        payload = compress(payload, BestCompression, dfGzip)

    # Encrypt result body 
    let (encData, mac) = encrypt(ctx.sessionKey, taskResult.header.nonce, payload, taskResult.header.seqNr)

    # Set authentication tag (MAC)
    taskResult.header.mac = mac

    # Serialize header 
    let header = packer.serializeHeader(taskResult.header, uint32(encData.len))

    return header & encData 