import strutils, strformat, streams
import ../utils
import ../../common/types
import ../../common/serialize

proc serializeTask*(cq: Conquest, task: Task): seq[byte] = 

    var packer = initTaskPacker() 

    # Serialize payload
    packer
        .add(task.taskId)
        .add(task.agentId)
        .add(task.listenerId)
        .add(task.timestamp)
        .add(task.command)
        .add(task.argCount)

    for arg in task.args:
        packer.addArgument(arg)

    let payload = packer.pack() 
    packer.reset()

    # TODO: Encrypt payload body

    # Serialize header 
    packer
        .add(task.header.magic)
        .add(task.header.version)
        .add(task.header.packetType)
        .add(task.header.flags)
        .add(task.header.seqNr) 
        .add(cast[uint32](payload.len))
        .addData(task.header.hmac)

    let header = packer.pack() 

    # TODO: Calculate and patch HMAC

    return header & payload
