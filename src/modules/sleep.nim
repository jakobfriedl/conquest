import ../common/[types, utils]

# Define function prototype
proc executeSleep(ctx: AgentCtx, task: Task): TaskResult 
proc executeSleepmask(ctx: AgentCtx, task: Task): TaskResult 

# Module definition
let commands* = @[
    Command(
        name: protect("sleep"),
        commandType: CMD_SLEEP,
        description: protect("Update sleep delay settings."),
        example: protect("sleep 5 15"),
        arguments: @[
            Argument(name: protect("delay"), description: protect("Delay in seconds."), argumentType: INT, isRequired: true),
            Argument(name: protect("jitter"), description: protect("Jitter in percent (0-100)."), argumentType: INT, isRequired: false)
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

# Implement execution functions
when not defined(agent):
    proc executeSleep(ctx: AgentCtx, task: Task): TaskResult = nil
    proc executeSleepmask(ctx: AgentCtx, task: Task): TaskResult = nil
