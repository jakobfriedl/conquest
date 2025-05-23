import winim, osproc, strutils, strformat

import ../types

proc taskShell*(command: seq[string]): tuple[output: TaskResult, status: TaskStatus] = 

    echo "Executing command: ", command.join(" ")

    try: 
        let (output, status) = execCmdEx(command.join(" ")) 
        return (output, Completed) 

    except CatchableError as err: 
        return (fmt"An error occured: {err.msg}" & "\n", Failed) 