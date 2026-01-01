import ../common/[types, utils]

# Declare function prototypes
proc executePs(ctx: AgentCtx, task: Task): TaskResult
proc executeEnv(ctx: AgentCtx, task: Task): TaskResult

# Module definition
let module* = Module(
    name: protect("systeminfo"),
    description: protect("Retrieve information about the target system and environment."),
    moduleType: MODULE_SYSTEMINFO,
    commands: @[
        Command(
            name: protect("ps"),
            commandType: CMD_PS,
            description: protect("Display running processes."),
            example: protect("ps"),
            arguments: @[],
            execute: executePs
        ),
        Command(
            name: protect("env"),
            commandType: CMD_ENV,
            description: protect("Display environment variables."),
            example: protect("env"),
            arguments: @[],
            execute: executeEnv
        )
    ]
)

# Implement execution functions
when not defined(agent):
    proc executePs(ctx: AgentCtx, task: Task): TaskResult = nil
    proc executeEnv(ctx: AgentCtx, task: Task): TaskResult = nil

