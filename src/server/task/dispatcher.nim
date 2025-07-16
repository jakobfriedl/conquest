import argparse, times, strformat, terminal, sequtils
import ../../types
import ../utils

proc createTask*(cq: Conquest, command: CommandType, args: string, message: string) =
    let
        date = now().format("dd-MM-yyyy HH:mm:ss")
        task = Task(
            id: generateUUID(),
            agent: cq.interactAgent.name,
            command: command,
            args: args,
        )
    
    cq.interactAgent.tasks.add(task)
    cq.writeLine(fgBlack, styleBright, fmt"[{date}] [*] ", resetStyle, message)