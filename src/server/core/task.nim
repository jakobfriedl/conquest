import strformat, terminal, tables, sequtils, strutils

import ../protocol/parser
import ../core/logger
import ../../modules/manager
import ../../common/types

proc displayHelp(cq: Conquest) = 
    cq.output("Available commands:")
    cq.output(" * back")
    for key, cmd in getAvailableCommands(): 
        cq.output(fmt" * {cmd.name:<15}{cmd.description}")
    cq.output()

proc displayCommandHelp(cq: Conquest, command: Command) = 
    var usage = command.name & " " & command.arguments.mapIt(
        if it.isRequired: fmt"<{it.name}>" else: fmt"[{it.name}]"
    ).join(" ")

    if command.example != "": 
        usage &= "\nExample : " & command.example

    cq.output(fmt"""
{command.description}

Usage   : {usage}
""")

    if command.arguments.len > 0:
        cq.output("Arguments:\n")

        let header = @["Name", "Type", "Required", "Description"]
        cq.output(fmt"   {header[0]:<15} {header[1]:<6} {header[2]:<8} {header[3]}")
        cq.output(fmt"   {'-'.repeat(15)} {'-'.repeat(6)} {'-'.repeat(8)} {'-'.repeat(20)}")
        
        for arg in command.arguments: 
            let isRequired = if arg.isRequired: "YES" else: "NO"
            cq.output(fmt" * {arg.name:<15} {($arg.argumentType).toUpperAscii():<6} {isRequired:>8} {arg.description}")

        cq.output()

proc handleHelp(cq: Conquest, parsed: seq[string]) = 
    try: 
        # Try parsing the first argument passed to 'help' as a command
        cq.displayCommandHelp(getCommandByName(parsed[1]))
    except IndexDefect:
        # 'help' command is called without additional parameters
        cq.displayHelp()
    except ValueError: 
        # Command was not found
        cq.error(fmt"The command '{parsed[1]}' does not exist." & '\n')

proc handleAgentCommand*(cq: Conquest, input: string) = 
    # Return if no command (or just whitespace) is entered
    if input.replace(" ", "").len == 0: return

    cq.input(input)

    # Convert user input into sequence of string arguments
    let parsedArgs = parseInput(input)
    
    # Handle 'back' command
    if parsedArgs[0] == "back": 
        cq.interactAgent = nil 
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
        cq.info(fmt"Tasked agent to {command.description.toLowerAscii()}")

    except CatchableError: 
        cq.error(getCurrentExceptionMsg() & "\n")
        return