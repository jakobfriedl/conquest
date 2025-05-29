import os, strutils, strformat, base64

import ../types

proc taskSleep*(task: Task): TaskResult = 

    echo fmt"Sleeping for {task.args[0]} seconds."

    try: 
        sleep(parseInt(task.args[0]) * 1000) 
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