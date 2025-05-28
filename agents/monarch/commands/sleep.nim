import os, strutils, strformat

import ../types

proc taskSleep*(delay: int): tuple[output: TaskResult, status: TaskStatus] = 

    echo fmt"Sleeping for {$delay} seconds."

    try: 
        sleep(delay * 1000) 
        return ("", Completed) 

    except CatchableError as err: 
        return (fmt"An error occured: {err.msg}" & "\n", Failed) 