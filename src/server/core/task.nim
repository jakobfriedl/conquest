import times, strformat, terminal, tables, json, sequtils, strutils

import ../utils
import ../message/parser
import ../../modules/manager
import ../../common/[types, utils]

proc displayHelp(cq: Conquest) = 
    cq.writeLine("Available commands:")
    cq.writeLine(" * back")
    for key, cmd in getAvailableCommands(): 
        cq.writeLine(fmt" * {cmd.name:<15}{cmd.description}")
    cq.writeLine()

proc displayCommandHelp(cq: Conquest, command: Command) = 
    var usage = command.name & " " & command.arguments.mapIt(
        if it.isRequired: fmt"<{it.name}>" else: fmt"[{it.name}]"
    ).join(" ")

    if command.example != "": 
        usage &= "\nExample : " & command.example

    cq.writeLine(fmt"""
{command.description}

Usage   : {usage}
""")

    if command.arguments.len > 0:
        cq.writeLine("Arguments:\n")

        let header = @["Name", "Type", "Required", "Description"]
        cq.writeLine(fmt"   {header[0]:<15} {header[1]:<6} {header[2]:<8} {header[3]}")
        cq.writeLine(fmt"   {'-'.repeat(15)} {'-'.repeat(6)} {'-'.repeat(8)} {'-'.repeat(20)}")
        
        for arg in command.arguments: 
            let isRequired = if arg.isRequired: "YES" else: "NO"
            cq.writeLine(fmt" * {arg.name:<15} {($arg.argumentType).toUpperAscii():<6} {isRequired:>8} {arg.description}")

        cq.writeLine()

proc handleHelp(cq: Conquest, parsed: seq[string]) = 
    try: 
        # Try parsing the first argument passed to 'help' as a command
        cq.displayCommandHelp(getCommandByName(parsed[1]))
    except IndexDefect:
        # 'help' command is called without additional parameters
        cq.displayHelp()
    except ValueError: 
        # Command was not found
        cq.writeLine(fgRed, styleBright, fmt"[-] The command '{parsed[1]}' does not exist." & '\n')

proc handleAgentCommand*(cq: Conquest, input: string) = 
    # Return if no command (or just whitespace) is entered
    if input.replace(" ", "").len == 0: return

    let date: string = now().format("dd-MM-yyyy HH:mm:ss")
    cq.writeLine(fgBlue, styleBright, fmt"[{date}] ", fgYellow, fmt"[{cq.interactAgent.agentId}] ", resetStyle, styleBright, input)

    # Convert user input into sequence of string arguments
    let parsedArgs = parseInput(input)
    
    # Handle 'back' command
    if parsedArgs[0] == "back": 
        return

    # Handle 'help' command 
    if parsedArgs[0] == "help": 
        cq.handleHelp(parsedArgs)
        return

    # Handle commands with actions on the agent
    try: 
        let 
            command = getCommandByName(parsedArgs[0])
            task = cq.createTask(command, parsedArgs[1..^1])

        # Add task to queue
        cq.interactAgent.tasks.add(task)
        cq.writeLine(fgBlack, styleBright, fmt"[{date}] [*] ", resetStyle, fmt"Tasked agent to {command.description.toLowerAscii()}")

    except CatchableError: 
        cq.writeLine(fgRed, styleBright, fmt"[-] {getCurrentExceptionMsg()}" & "\n")
        return