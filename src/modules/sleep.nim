import ../common/[types, utils]

# Define function prototype
proc executeSleep(ctx: AgentCtx, task: Task): TaskResult 
proc executeSleepmask(ctx: AgentCtx, task: Task): TaskResult 

# Module definition
let module* = Module(
    name: protect("sleep"), 
    description: protect("Change sleep settings."),
    moduleType: MODULE_SLEEP,
    commands: @[
        Command(
            name: protect("sleep"),
            commandType: CMD_SLEEP,
            description: protect("Update sleep delay settings."),
            example: protect("sleep 5"),
            arguments: @[
                Argument(name: protect("delay"), description: protect("Delay in seconds."), argumentType: INT, isRequired: true)
            ],
            execute: executeSleep
        ),
        Command(
            name: protect("sleepmask"),
            commandType: CMD_SLEEPMASK,
            description: protect("Update sleepmask settings."),
            example: protect("sleepmask ekko true"),
            arguments: @[
                Argument(name: protect("technique"), description: protect("Sleep obfuscation technique (NONE, EKKO, ZILEAN, FOLIAGE). Executing without arguments retrieves current sleepmask settings."), argumentType: STRING, isRequired: false),
                Argument(name: protect("spoof"), description: protect("Use stack spoofing to obfuscate the call stack."), argumentType: BOOL, isRequired: false)
            ],
            execute: executeSleepmask
        )
    ]
)

# Implement execution functions
when not defined(agent):
    proc executeSleep(ctx: AgentCtx, task: Task): TaskResult = nil
    proc executeSleepmask(ctx: AgentCtx, task: Task): TaskResult = nil

when defined(agent): 

    import os, strutils, strformat
    import ../agent/core/io
    import ../agent/protocol/result
    import ../common/utils

    proc executeSleep(ctx: AgentCtx, task: Task): TaskResult = 

        try: 
            # Parse task parameter
            let delay = int(Bytes.toUint32(task.args[0].data))

            # Updating sleep in agent context
            print fmt"   [>] Setting sleep delay to {delay} seconds."
            ctx.sleep = delay
                    
            return createTaskResult(task, STATUS_COMPLETED, RESULT_NO_OUTPUT, @[])

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

    proc executeSleepmask(ctx: AgentCtx, task: Task): TaskResult = 

        try: 
            print fmt"   [>] Updating sleepmask settings."
            
            case int(task.argCount): 
            of 0: 
                # Retrieve sleepmask settings 
                let response = fmt"Sleepmask settings: Technique: {$ctx.sleepTechnique}, Delay: {$ctx.sleep}ms, Stack spoofing: {$ctx.spoofStack}"
                return createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(response))

            of 1: 
                # Only set the sleepmask technique
                let technique = parseEnum[SleepObfuscationTechnique](Bytes.toString(task.args[0].data).toUpperAscii())
                ctx.sleepTechnique = technique

            else: 
                # Set sleepmask technique and stack-spoofing configuration
                let technique = parseEnum[SleepObfuscationTechnique](Bytes.toString(task.args[0].data).toUpperAscii())
                ctx.sleepTechnique = technique

                let spoofStack = cast[bool](task.args[1].data[0]) # BOOLEAN values are just 1 byte
                ctx.spoofStack = spoofStack

            return createTaskResult(task, STATUS_COMPLETED, RESULT_NO_OUTPUT, @[])

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))
