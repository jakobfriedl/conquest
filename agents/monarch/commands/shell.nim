import winim, osproc, strutils

import ../types

proc taskShell*(command: seq[string]): TaskResult = 

    echo command.join(" ")
    let (output, status) = execCmdEx(command.join(" ")) 
    
    return output 
