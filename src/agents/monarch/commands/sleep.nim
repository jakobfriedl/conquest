import os, strutils, strformat

import ../[agentTypes, utils]
import ../task/result
import ../../../common/[types, serialize]

proc taskSleep*(config: AgentConfig, task: Task): TaskResult = 

    try: 
        # Parse task parameter
        let delay = int(task.args[0].data.toUint32())

        echo fmt"   [>] Sleeping for {delay} seconds."
        
        sleep(delay * 1000) 
    
        # Updating sleep in agent config
        config.sleep = delay
        
        return createTaskResult(task, STATUS_COMPLETED, RESULT_NO_OUTPUT, @[])

    except CatchableError as err: 
        return createTaskResult(task, STATUS_FAILED, RESULT_STRING, err.msg.toBytes())
