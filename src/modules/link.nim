import ../common/[types, utils]

# Define function prototype
proc executeLink(ctx: AgentCtx, task: Task): TaskResult 
proc executeUnlink(ctx: AgentCtx, task: Task): TaskResult 

# Module definition
let commands* = @[
        Command(
            name: protect("link"),
            commandType: CMD_LINK,
            description: protect("Create a link to a SMB agent."),
            example: protect("link DC01 msagent_1234"),
            arguments: @[
                Argument(name: protect("host"), description: protect("Host where the SMB agent is running on."), argumentType: STRING, isRequired: true),
                Argument(name: protect("pipe"), description: protect("Name of the named pipe (SMB listener)."), argumentType: STRING, isRequired: true)
            ],
            execute: executeLink
        ),
        Command(
            name: protect("unlink"),
            commandType: CMD_UNLINK,
            description: protect("Remove a link to a SMB agent."),
            example: protect("unlink C804A284"),
            arguments: @[
                Argument(name: protect("agent"), description: protect("ID of the agent to unlink."), argumentType: STRING, isRequired: true)
            ],
            execute: executeUnlink
        )
    ] 

# Implement execution functions
when not defined(agent):
    proc executeLink(ctx: AgentCtx, task: Task): TaskResult = nil
    proc executeUnlink(ctx: AgentCtx, task: Task): TaskResult = nil
