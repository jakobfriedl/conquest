import argparse, times, strformat, terminal, nanoid, sequtils
import ../../types

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