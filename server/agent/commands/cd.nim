import nanoid, sequtils, strutils, strformat, terminal, times
import ../../types

proc taskSetWorkingDirectory*(cq: Conquest, arguments: seq[string]) = 

    # Create a new task 
    let 
        date: string = now().format("dd-MM-yyyy HH:mm:ss")
        task = Task(
            id: generate(alphabet=join(toSeq('A'..'Z'), ""), size=8),
            agent: cq.interactAgent.name, 
            command: SetWorkingDirectory,
            args: arguments,
        )

    # Add new task to the agent's task queue
    cq.interactAgent.tasks.add(task)

    cq.writeLine(fgBlack, styleBright, fmt"[{date}] [*] ", resetStyle, fmt"Tasked agent to change current working directory.")