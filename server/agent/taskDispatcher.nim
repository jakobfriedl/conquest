import nanoid, sequtils, strutils, strformat, terminal, times, json
import ../types
import ../db/database

# Generic task creation procedure
proc createTask*(cq: Conquest, command: CommandType, args: string, message: string) =
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