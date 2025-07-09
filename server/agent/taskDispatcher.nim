import nanoid, sequtils, strutils, strformat, terminal, times, json
import ../types
import ../db/database

# Generic task creation procedure
proc createTask(cq: Conquest, command: TaskCommand, args: string, message: string) =
    let
        date = now().format("dd-MM-yyyy HH:mm:ss")
        task = Task(
            id: generate(alphabet=join(toSeq('A'..'Z'), ""), size=8),
            agent: cq.interactAgent.name,
            command: command,
            args: args,
        )
    
    cq.interactAgent.tasks.add(task)
    cq.writeLine(fgBlack, styleBright, fmt"[{date}] [*] ", resetStyle, message)

# Agent task functions
proc taskExecuteSleep*(cq: Conquest, delay: int) = 
    if delay < 0: 
        cq.writeLine(fgRed, styleBright, "[-] Invalid sleep delay value.")
        return

    # Update 'sleep' value in database 
    if not cq.dbUpdateSleep(cq.interactAgent.name, delay): 
        return

    # Construct payload 
    let payload = %*{ "delay": delay }

    # Use the generic createTask function
    createTask(cq, Sleep, $payload, "Tasked agent to update sleep settings.")

proc taskExecuteShell*(cq: Conquest, command: string, arguments: seq[string]) = 
    let payload = %*{ "command": command, "arguments": arguments.join(" ")}
    cq.createTask(ExecuteShell, $payload, "Tasked agent to execute shell command.")

proc taskGetWorkingDirectory*(cq: Conquest) =
    cq.createTask(GetWorkingDirectory, "", "Tasked agent to get current working directory.")

proc taskSetWorkingDirectory*(cq: Conquest, arguments: seq[string]) =
    let payload = %*{ "directory": arguments.join(" ").replace("\"").replace("'")}
    cq.createTask(SetWorkingDirectory, $payload, "Tasked agent to change current working directory.")

proc taskListDirectory*(cq: Conquest, arguments: seq[string]) =
    let payload = %*{ "directory": arguments.join(" ").replace("\"").replace("'")}
    cq.createTask(ListDirectory, $payload, "Tasked agent to list files and directories.")

proc taskRemoveFile*(cq: Conquest, arguments: seq[string]) =
    let payload = %*{ "file": arguments.join(" ").replace("\"").replace("'")}
    cq.createTask(RemoveFile, $payload, "Tasked agent to remove file.")

proc taskRemoveDirectory*(cq: Conquest, arguments: seq[string]) =
    let payload = %*{ "directory": arguments.join(" ").replace("\"").replace("'")}
    cq.createTask(RemoveDirectory, $payload, "Tasked agent to remove directory.")

proc taskExecuteBof*(cq: Conquest, file: string, arguments: seq[string]) = 
    
    # Verify that the object file exists 
    
    # Read object file into memory and base64-encode it

    # Create the payload package, consisting of base64-encoded object file and the arguments passed to it
    # Best way would be a custom binary structure, but for the time being, a JSON string would work, which is deserialized and parsed by the agent
    #[
        let payload = %*
        {
            "file": "AAAA...AA=="
            "arguments": "arg1 arg2 123"
        }
    ]#

    # Create a new task 
    discard