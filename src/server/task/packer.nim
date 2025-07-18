import strutils, strformat, streams
import ../utils
import ../../common/types
import ../../common/serialize

proc serializeTask*(cq: Conquest, task: Task): seq[byte] = 

    var packer = initTaskPacker() 

    # Serialize payload
    packer
        .addToPayload(task.taskId)
        .addToPayload(task.agentId)
        .addToPayload(task.listenerId)
        .addToPayload(task.timestamp)
        .addToPayload(task.command)
        .addToPayload(task.argCount)

    for arg in task.args:
        packer.addArgument(arg)

    let payload = packer.packPayload() 

    # TODO: Encrypt payload body

    # Serialize header 
    packer
        .addToHeader(task.header.magic)
        .addToHeader(task.header.version)
        .addToHeader(task.header.packetType)
        .addToHeader(task.header.flags)
        .addToHeader(task.header.seqNr)
        .addToHeader(cast[uint32](payload.len))
        .addDataToHeader(task.header.hmac)

    let header = packer.packHeader() 

    # TODO: Calculate and patch HMAC

    return header & payload
