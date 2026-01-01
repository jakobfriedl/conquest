import ../common/[types, utils]

# Define function prototypes
proc executePwd(ctx: AgentCtx, task: Task): TaskResult
proc executeCd(ctx: AgentCtx, task: Task): TaskResult
proc executeDir(ctx: AgentCtx, task: Task): TaskResult
proc executeRm(ctx: AgentCtx, task: Task): TaskResult
proc executeRmdir(ctx: AgentCtx, task: Task): TaskResult
proc executeMove(ctx: AgentCtx, task: Task): TaskResult 
proc executeCopy(ctx: AgentCtx, task: Task): TaskResult 

# Module definition
let module* = Module(
    name: protect("filesystem"),
    description: protect("Conduct simple filesystem operations via Windows API."),
    moduleType: MODULE_FILESYSTEM,
    commands: @[
        Command(
            name: protect("pwd"),
            commandType: CMD_PWD,
            description: protect("Retrieve current working directory."),
            example: protect("pwd"),
            arguments: @[],
            execute: executePwd
        ),
        Command(
            name: protect("cd"),
            commandType: CMD_CD,
            description: protect("Change current working directory."),
            example: protect("cd C:\\Windows\\Tasks"),
            arguments: @[
                Argument(name: protect("directory"), description: protect("Relative or absolute path of the directory to change to."), argumentType: STRING, isRequired: true)
            ],
            execute: executeCd
        ),
        Command(
            name: protect("ls"),
            commandType: CMD_LS,
            description: protect("List files and directories."),
            example: protect("ls C:\\Users\\Administrator\\Desktop"),
            arguments: @[
                Argument(name: protect("directory"), description: protect("Relative or absolute path. Default: current working directory."), argumentType: STRING, isRequired: false)
            ],
            execute: executeDir
        ),
        Command(
            name: protect("rm"), 
            commandType: CMD_RM,
            description: protect("Remove a file."),
            example: protect("rm C:\\Windows\\Tasks\\payload.exe"),
            arguments: @[
                Argument(name: protect("file"), description: protect("Relative or absolute path to the file to delete."), argumentType: STRING, isRequired: true)
            ],
            execute: executeRm
        ),
        Command(
            name: protect("rmdir"),
            commandType: CMD_RMDIR,
            description: protect("Remove a directory."),
            example: protect("rm C:\\Payloads"),
            arguments: @[
                Argument(name: protect("directory"), description: protect("Relative or absolute path to the directory to delete."), argumentType: STRING, isRequired: true)
            ],
            execute: executeRmdir
        ),
        Command(
            name: protect("move"),
            commandType: CMD_MOVE,
            description: protect("Move a file or directory."),
            example: protect("move source.exe C:\\Windows\\Tasks\\destination.exe"),
            arguments: @[
                Argument(name: protect("source"), description: protect("Source file path."), argumentType: STRING, isRequired: true),
                Argument(name: protect("destination"), description: protect("Destination file path."), argumentType: STRING, isRequired: true)
            ],
            execute: executeMove
        ),
        Command(
            name: protect("copy"),
            commandType: CMD_COPY,
            description: protect("Copy a file or directory."),
            example: protect("copy source.exe C:\\Windows\\Tasks\\destination.exe"),
            arguments: @[
                Argument(name: protect("source"), description: protect("Source file path."), argumentType: STRING, isRequired: true),
                Argument(name: protect("destination"), description: protect("Destination file path."), argumentType: STRING, isRequired: true)
            ],
            execute: executeCopy
        )
    ]
)

# Implementation of the execution functions
when not defined(agent):
    proc executePwd(ctx: AgentCtx, task: Task): TaskResult = nil
    proc executeCd(ctx: AgentCtx, task: Task): TaskResult = nil
    proc executeDir(ctx: AgentCtx, task: Task): TaskResult = nil
    proc executeRm(ctx: AgentCtx, task: Task): TaskResult = nil
    proc executeRmdir(ctx: AgentCtx, task: Task): TaskResult = nil
    proc executeMove(ctx: AgentCtx, task: Task): TaskResult = nil
    proc executeCopy(ctx: AgentCtx, task: Task): TaskResult = nil
