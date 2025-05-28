import nanoid, sequtils, strutils, strformat, terminal, times
import ../../types
import ../../db/database

proc taskExecuteSleep*(cq: Conquest, delay: int) = 

    # Update 'sleep' value in database 
    if not cq.dbUpdateSleep(cq.interactAgent.name, delay): 
        return 

    # Create a new task 
    let 
        date: string = now().format("dd-MM-yyyy HH:mm:ss")
        task = Task(
            id: generate(alphabet=join(toSeq('A'..'Z'), ""), size=8),
            agent: cq.interactAgent.name, 
            command: Sleep,
            args: @[$delay],
            result: "",
            status: Created
        )

    # Add new task to the agent's task queue
    cq.interactAgent.tasks.add(task)

    cq.writeLine(fgBlack, styleBright, fmt"[*] [{task.id}] ", resetStyle, "Tasked agent to update sleep settings.")