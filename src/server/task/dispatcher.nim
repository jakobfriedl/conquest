import times, strformat, terminal, tables, json, sequtils, strutils
import ./[parser, packer]
import ../utils
import ../../common/types

proc initAgentCommands*(): Table[string, Command] = 
    var commands = initTable[string, Command]()

    commands["shell"] = Command(
        name: "shell",
        commandType: CMD_SHELL,
        description: "Execute a shell command and retrieve the output.",
        example: "shell whoami /all",
        arguments: @[
            Argument(name: "command", description: "Command to be executed.", argumentType: STRING, isRequired: true),
            Argument(name: "arguments", description: "Arguments to be passed to the command.", argumentType: STRING, isRequired: false)
        ]
    )

    commands["sleep"] = Command(
        name: "sleep",
        commandType: CMD_SLEEP,
        description: "Update sleep delay configuration.",
        example: "sleep 5",
        arguments: @[
            Argument(name: "delay", description: "Delay in seconds.", argumentType: INT, isRequired: true)
        ]
    )

    commands["pwd"] = Command(
        name: "pwd",
        commandType: CMD_PWD,
        description: "Retrieve current working directory.",
        example: "pwd",
        arguments: @[]
    )

    commands["cd"] = Command(
        name: "cd",
        commandType: CMD_CD,
        description: "Change current working directory.",
        example: "cd C:\\Windows\\Tasks",
        arguments: @[
            Argument(name: "directory", description: "Relative or absolute path of the directory to change to.", argumentType: STRING, isRequired: true)
        ]
    )

    commands["ls"] = Command(
        name: "ls",
        commandType: CMD_LS,
        description: "List files and directories.",
        example: "ls C:\\Users\\Administrator\\Desktop",
        arguments: @[
            Argument(name: "directory", description: "Relative or absolute path. Default: current working directory.", argumentType: STRING, isRequired: false)
        ]
    )

    commands["rm"] = Command(
        name: "rm", 
        commandType: CMD_RM,
        description: "Remove a file.",
        example: "rm C:\\Windows\\Tasks\\payload.exe",
        arguments: @[
            Argument(name: "file", description: "Relative or absolute path to the file to delete.", argumentType: STRING, isRequired: true)
        ]
    )

    commands["rmdir"] = Command(
        name: "rmdir",
        commandType: CMD_RMDIR,
        description: "Remove a directory.",
        example: "rm C:\\Payloads",
        arguments: @[
            Argument(name: "directory", description: "Relative or absolute path to the directory to delete.", argumentType: STRING, isRequired: true)
        ]
    )

    commands["move"] = Command(
        name: "move",
        commandType: CMD_MOVE,
        description: "Move a file or directory.",
        example: "move source.exe C:\\Windows\\Tasks\\destination.exe",
        arguments: @[
            Argument(name: "source", description: "Source file path.", argumentType: STRING, isRequired: true),
            Argument(name: "destination", description: "Destination file path.", argumentType: STRING, isRequired: true)
        ]
    )

    commands["copy"] = Command(
        name: "copy",
        commandType: CMD_COPY,
        description: "Copy a file or directory.",
        example: "copy source.exe C:\\Windows\\Tasks\\destination.exe",
        arguments: @[
            Argument(name: "source", description: "Source file path.", argumentType: STRING, isRequired: true),
            Argument(name: "destination", description: "Destination file path.", argumentType: STRING, isRequired: true)
        ]
    )

    return commands 

let commands = initAgentCommands() 

proc getCommandFromTable(input: string, commands: Table[string, Command]): Command =
    try:
        let command = commands[input]
        return command
    except ValueError: 
        raise newException(ValueError, fmt"The command '{input}' does not exist.")

proc displayHelp(cq: Conquest, commands: Table[string, Command]) = 
    cq.writeLine("Available commands:")
    cq.writeLine(" * back")
    for key, cmd in commands: 
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

proc handleHelp(cq: Conquest, parsed: seq[string], commands: Table[string, Command]) = 
    try: 
        # Try parsing the first argument passed to 'help' as a command
        cq.displayCommandHelp(getCommandFromTable(parsed[1],  commands))
    except IndexDefect:
        # 'help' command is called without additional parameters
        cq.displayHelp(commands)
    except ValueError: 
        # Command was not found
        cq.writeLine(fgRed, styleBright, fmt"[-] The command '{parsed[1]}' does not exist." & '\n')

proc handleAgentCommand*(cq: Conquest, input: string) = 
    # Return if no command (or just whitespace) is entered
    if input.replace(" ", "").len == 0: return

    let date: string = now().format("dd-MM-yyyy HH:mm:ss")
    cq.writeLine(fgBlue, styleBright, fmt"[{date}] ", fgYellow, fmt"[{cq.interactAgent.name}] ", resetStyle, styleBright, input)

    # Convert user input into sequence of string arguments
    let parsedArgs = parseInput(input)
    
    # Handle 'back' command
    if parsedArgs[0] == "back": 
        return

    # Handle 'help' command 
    if parsedArgs[0] == "help": 
        cq.handleHelp(parsedArgs, commands)
        return

    # Handle commands with actions on the agent
    try: 
        let 
            command = getCommandFromTable(parsedArgs[0], commands)
            task = cq.parseTask(command, parsedArgs[1..^1])
            taskData: seq[byte] = cq.serializeTask(task)    

        # cq.writeLine(taskData.toHexDump())

        # Add task to queue
        cq.interactAgent.tasks.add(taskData)
        cq.writeLine(fgBlack, styleBright, fmt"[{date}] [*] ", resetStyle, fmt"Tasked agent to {command.description.toLowerAscii()}")

    except CatchableError: 
        cq.writeLine(fgRed, styleBright, fmt"[-] {getCurrentExceptionMsg()}" & "\n")
        return