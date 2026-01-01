import ../common/[types, utils]

# Define function prototype
proc executeExit(ctx: AgentCtx, task: Task): TaskResult 
proc executeSelfDestroy(ctx: AgentCtx, task: Task): TaskResult 

# Module definition
let commands* = @[
        Command(
            name: protect("exit"),
            commandType: CMD_EXIT,
            description: protect("Exit the agent."),
            example: protect("exit process"),
            arguments: @[
                Argument(name: protect("type"), description: protect("Available options: PROCESS/THREAD. Default: PROCESS."), argumentType: STRING, isRequired: false),
            ],
            execute: executeExit
        ),
        Command(
            name: protect("self-destruct"),
            commandType: CMD_SELF_DESTRUCT,
            description: protect("Exit the agent and delete the executable from disk."),
            example: protect("self-destruct"),
            arguments: @[
            ],
            execute: executeSelfDestroy
        )
    ] 

# Implement execution functions
when not defined(agent):
    proc executeExit(ctx: AgentCtx, task: Task): TaskResult = nil
    proc executeSelfDestroy(ctx: AgentCtx, task: Task): TaskResult = nil 

