import os, strutils, strformat, winim, times, algorithm

import ../core/taskresult
import ../../../common/[types, utils]

# Retrieve current working directory
proc taskPwd*(config: AgentConfig, task: Task): TaskResult = 

    echo fmt"   [>] Retrieving current working directory."

    try: 
        # Get current working directory using GetCurrentDirectory
        let 
            buffer = newWString(MAX_PATH + 1)
            length = GetCurrentDirectoryW(MAX_PATH, &buffer)
        
        if length == 0:
            raise newException(OSError, fmt"Failed to get working directory ({GetLastError()}).")

        let output = $buffer[0 ..< (int)length] & "\n"
        return createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, output.toBytes())

    except CatchableError as err: 
        return createTaskResult(task, STATUS_FAILED, RESULT_STRING, err.msg.toBytes())


# Change working directory
proc taskCd*(config: AgentConfig, task: Task): TaskResult = 

    # Parse arguments
    let targetDirectory = task.args[0].data.toString()

    echo fmt"   [>] Changing current working directory to {targetDirectory}."

    try: 
        # Get current working directory using GetCurrentDirectory
        if SetCurrentDirectoryW(targetDirectory) == FALSE:         
            raise newException(OSError, fmt"Failed to change working directory ({GetLastError()}).")

        return createTaskResult(task, STATUS_COMPLETED, RESULT_NO_OUTPUT, @[])

    except CatchableError as err: 
        return createTaskResult(task, STATUS_FAILED, RESULT_STRING, err.msg.toBytes())


# List files and directories at a specific or at the current path
proc taskDir*(config: AgentConfig, task: Task): TaskResult = 

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
                raise newException(OSError, fmt"Failed to get working directory ({GetLastError()}).")

            targetDirectory = $cwdBuffer[0 ..< (int)cwdLength]

        of 1:  
            targetDirectory = task.args[0].data.toString()
        else:
            discard

        echo fmt"   [>] Listing files and directories in {targetDirectory}."
            
        # Prepare search pattern (target directory + \*)
        let searchPattern = targetDirectory & "\\*"
        let searchPatternW = newWString(searchPattern)
        
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
            raise newException(OSError, fmt"Failed to find files ({GetLastError()}).")
        
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
                        dateTimeStr = "01/01/1970  00:00:00"
                    
                    if FileTimeToLocalFileTime(&findData.ftLastWriteTime, &localTime) != 0 and FileTimeToSystemTime(&localTime, &systemTime) != 0:
                        # Format date and time in PowerShell style
                        dateTimeStr = fmt"{systemTime.wDay:02d}/{systemTime.wMonth:02d}/{systemTime.wYear}  {systemTime.wHour:02d}:{systemTime.wMinute:02d}:{systemTime.wSecond:02d}"
                    
                    # Format file size
                    var sizeStr = ""
                    if isDir:
                        sizeStr = "<DIR>"
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
            output &= fmt"{totalDirs} dir(s)" & "\n"

            return createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, output.toBytes())

    except CatchableError as err: 
        return createTaskResult(task, STATUS_FAILED, RESULT_STRING, err.msg.toBytes())


# Remove file 
proc taskRm*(config: AgentConfig, task: Task): TaskResult = 

    # Parse arguments
    let target = task.args[0].data.toString()

    echo fmt"   [>] Deleting file {target}."

    try: 
        if DeleteFile(target) == FALSE:         
            raise newException(OSError, fmt"Failed to delete file ({GetLastError()}).")

        return createTaskResult(task, STATUS_COMPLETED, RESULT_NO_OUTPUT, @[])

    except CatchableError as err: 
        return createTaskResult(task, STATUS_FAILED, RESULT_STRING, err.msg.toBytes())
        

# Remove directory
proc taskRmdir*(config: AgentConfig, task: Task): TaskResult = 

    # Parse arguments
    let target = task.args[0].data.toString()

    echo fmt"   [>] Deleting directory {target}."

    try: 
        if RemoveDirectoryA(target) == FALSE:         
            raise newException(OSError, fmt"Failed to delete directory ({GetLastError()}).")

        return createTaskResult(task, STATUS_COMPLETED, RESULT_NO_OUTPUT, @[])

    except CatchableError as err: 
        return createTaskResult(task, STATUS_FAILED, RESULT_STRING, err.msg.toBytes())

# Move file or directory
proc taskMove*(config: AgentConfig, task: Task): TaskResult = 

    # Parse arguments
    let 
        lpExistingFileName = task.args[0].data.toString()
        lpNewFileName = task.args[1].data.toString()

    echo fmt"   [>] Moving {lpExistingFileName} to {lpNewFileName}."

    try: 
        if MoveFile(lpExistingFileName, lpNewFileName) == FALSE:         
            raise newException(OSError, fmt"Failed to move file or directory ({GetLastError()}).")

        return createTaskResult(task, STATUS_COMPLETED, RESULT_NO_OUTPUT, @[])

    except CatchableError as err: 
        return createTaskResult(task, STATUS_FAILED, RESULT_STRING, err.msg.toBytes())


# Copy file or directory
proc taskCopy*(config: AgentConfig, task: Task): TaskResult = 

    # Parse arguments
    let 
        lpExistingFileName = task.args[0].data.toString()
        lpNewFileName = task.args[1].data.toString()

    echo fmt"   [>] Copying {lpExistingFileName} to {lpNewFileName}."

    try: 
        # Copy file to new location, overwrite if a file with the same name already exists
        if CopyFile(lpExistingFileName, lpNewFileName, FALSE) == FALSE:         
            raise newException(OSError, fmt"Failed to copy file or directory ({GetLastError()}).")

        return createTaskResult(task, STATUS_COMPLETED, RESULT_NO_OUTPUT, @[])

    except CatchableError as err: 
        return createTaskResult(task, STATUS_FAILED, RESULT_STRING, err.msg.toBytes())
