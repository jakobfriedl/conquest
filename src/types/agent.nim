import winim/lean
import tables
import ./[common, protocol] 

type 
    ExitType* {.size: sizeof(uint8).} = enum 
        EXIT_PROCESS = "process"
        EXIT_THREAD = "thread"

    ProcessInfo* = object 
        pid*: uint32
        ppid*: uint32 
        name*: string 
        user*: string
        session*: uint32

    DirectoryEntry* = object 
        name*: string 
        flags*: uint8
        size*: uint64
        lastWriteTime*: int64
        isLoaded*: bool

    TransportSettings* = ref object 
        listenerId*: string
        when defined(TRANSPORT_HTTP): 
            hosts*: string
        when defined(TRANSPORT_SMB): 
            pipe*: string 
            hPipe*: HANDLE

type
    AgentCtx* = ref object
        agentId*: string
        transport*: TransportSettings
        sleepSettings*: SleepSettings
        killDate*: int64
        sessionKey*: Key
        agentPublicKey*: Key
        profile*: Profile
        registered*: bool
        links*: Table[uint32, uint32]
        jobs*: seq[Job]
        hWakeupEvent*: HANDLE

    WorkerProc* = proc(ctx: AgentCtx, hWrite: HANDLE, hStopEvent: HANDLE, task: Task) {.nimcall, gcsafe.}

    ThreadParameter* = ref object
        ctx*: AgentCtx
        hWrite*: HANDLE
        hStopEvent*: HANDLE
        task*: Task
        worker*: WorkerProc
        failed*: bool

    JobState* = enum
        JOB_RUNNING   = 0'u8
        JOB_COMPLETED = 1'u8
        JOB_CANCELLED = 2'u8

    Job* = ref object
        task*: Task
        state*: JobState
        hThread*: HANDLE
        hRead*: HANDLE
        hWrite*: HANDLE
        hStopEvent*: HANDLE
        threadParams*: ThreadParameter