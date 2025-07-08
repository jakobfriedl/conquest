import nanoid, sequtils, strutils, strformat, terminal, times
import ../../types

proc taskGetWorkingDirectory*(cq: Conquest) = 

    # Create a new task 
    let 
        date: string = now().format("dd-MM-yyyy HH:mm:ss")
        task = Task(
            id: generate(alphabet=join(toSeq('A'..'Z'), ""), size=8),
            agent: cq.interactAgent.name, 
            command: GetWorkingDirectory,
            args: @[],
        )

    # Add new task to the agent's task queue
    cq.interactAgent.tasks.add(task)

    cq.writeLine(fgBlack, styleBright, fmt"[{date}] [*] ", resetStyle, "Tasked agent to get current working directory.")

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

proc taskListDirectory*(cq: Conquest, arguments: seq[string]) = 

    # Create a new task 
    let 
        date: string = now().format("dd-MM-yyyy HH:mm:ss")
        task = Task(
            id: generate(alphabet=join(toSeq('A'..'Z'), ""), size=8),
            agent: cq.interactAgent.name, 
            command: ListDirectory,
            args: arguments,
        )

    # Add new task to the agent's task queue
    cq.interactAgent.tasks.add(task)

    cq.writeLine(fgBlack, styleBright, fmt"[{date}] [*] ", resetStyle, fmt"Tasked agent to list files and directories.")

proc taskRemoveFile*(cq: Conquest, arguments: seq[string]) = 

    # Create a new task 
    let 
        date: string = now().format("dd-MM-yyyy HH:mm:ss")
        task = Task(
            id: generate(alphabet=join(toSeq('A'..'Z'), ""), size=8),
            agent: cq.interactAgent.name, 
            command: RemoveFile,
            args: arguments,
        )

    # Add new task to the agent's task queue
    cq.interactAgent.tasks.add(task)

    cq.writeLine(fgBlack, styleBright, fmt"[{date}] [*] ", resetStyle, fmt"Tasked agent to remove file.")

proc taskRemoveDirectory*(cq: Conquest, arguments: seq[string]) = 

    # Create a new task 
    let 
        date: string = now().format("dd-MM-yyyy HH:mm:ss")
        task = Task(
            id: generate(alphabet=join(toSeq('A'..'Z'), ""), size=8),
            agent: cq.interactAgent.name, 
            command: RemoveDirectory,
            args: arguments,
        )

    # Add new task to the agent's task queue
    cq.interactAgent.tasks.add(task)

    cq.writeLine(fgBlack, styleBright, fmt"[{date}] [*] ", resetStyle, fmt"Tasked agent to remove directory.")
