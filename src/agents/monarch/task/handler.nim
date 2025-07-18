import strutils, tables, json
import ../types 
import ../commands/commands
import sugar

proc handleTask*(config: AgentConfig, task: Task): TaskResult = 

    dump task

    # var taskResult = TaskResult
    # let handlers = {
    #     CMD_SLEEP: taskSleep,
    #     CMD_SHELL: taskShell,
    #     CMD_PWD: taskPwd,
    #     CMD_CD: taskCd,
    #     CMD_LS: taskDir,
    #     CMD_RM: taskRm,
    #     CMD_RMDIR: taskRmdir,
    #     CMD_MOVE: taskMove, 
    #     CMD_COPY: taskCopy
    # }.toTable

    # Handle task command
    # taskResult = handlers[task.command](task)
    # echo taskResult.data

    # Handle actions on specific commands
    # case task.command:
    # of CMD_SLEEP:         
    #     if taskResult.status == STATUS_COMPLETED: 
    #         # config.sleep = parseJson(task.args)["delay"].getInt() 
    #         discard
    # else: 
    #     discard

    # # Return the result
    # return taskResult