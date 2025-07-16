import times, strformat, terminal, tables, json, sequtils, strutils
import ./[parser, packer, dispatcher]
import ../utils
import ../../types

proc initAgentCommands*(): Table[CommandType, Command] = 
    var commands = initTable[CommandType, Command]()

    commands[ExecuteShell] = Command(
        name: "shell",
        commandType: ExecuteShell,
        description: "Execute a shell command and retrieve the output.",
        example: "shell whoami /all",
        arguments: @[
            Argument(name: "command", description: "Command to be executed.", argumentType: String, isRequired: true),
            Argument(name: "arguments", description: "Arguments to be passed to the command.", argumentType: String, isRequired: false)
        ]
    )

    commands[Sleep] = Command(
        name: "sleep",
        commandType: Sleep,
        description: "Update sleep delay configuration.",
        example: "sleep 5",
        arguments: @[
            Argument(name: "delay", description: "Delay in seconds.", argumentType: Int, isRequired: true)
        ]
    )

    commands[GetWorkingDirectory] = Command(
        name: "pwd",
        commandType: GetWorkingDirectory,
        description: "Retrieve current working directory.",
        example: "pwd",
        arguments: @[]
    )

    commands[SetWorkingDirectory] = Command(
        name: "cd",
        commandType: SetWorkingDirectory,
        description: "Change current working directory.",
        example: "cd C:\\Windows\\Tasks",
        arguments: @[
            Argument(name: "directory", description: "Relative or absolute path of the directory to change to.", argumentType: String, isRequired: true)
        ]
    )

    commands[ListDirectory] = Command(
        name: "ls",
        commandType: ListDirectory,
        description: "List files and directories.",
        example: "ls C:\\Users\\Administrator\\Desktop",
        arguments: @[
            Argument(name: "directory", description: "Relative or absolute path. Default: current working directory.", argumentType: String, isRequired: false)
        ]
    )

    commands[RemoveFile] = Command(
        name: "rm", 
        commandType: RemoveFile,
        description: "Remove a file.",
        example: "rm C:\\Windows\\Tasks\\payload.exe",
        arguments: @[
            Argument(name: "file", description: "Relative or absolute path to the file to delete.", argumentType: String, isRequired: true)
        ]
    )

    commands[RemoveDirectory] = Command(
        name: "rmdir",
        commandType: RemoveDirectory,
        description: "Remove a directory.",
        example: "rm C:\\Payloads",
        arguments: @[
            Argument(name: "directory", description: "Relative or absolute path to the directory to delete.", argumentType: String, isRequired: true)
        ]
    )

    commands[Move] = Command(
        name: "move",
        commandType: Move,
        description: "Move a file or directory.",
        example: "move source.exe C:\\Windows\\Tasks\\destination.exe",
        arguments: @[
            Argument(name: "source", description: "Source file path.", argumentType: String, isRequired: true),
            Argument(name: "destination", description: "Destination file path.", argumentType: String, isRequired: true)
        ]
    )

    commands[Copy] = Command(
        name: "copy",
        commandType: Copy,
        description: "Copy a file or directory.",
        example: "copy source.exe C:\\Windows\\Tasks\\destination.exe",
        arguments: @[
            Argument(name: "source", description: "Source file path.", argumentType: String, isRequired: true),
            Argument(name: "destination", description: "Destination file path.", argumentType: String, isRequired: true)
        ]
    )

    return commands 

let commands = initAgentCommands() 

proc getCommandFromTable(cmd: string, commands: Table[CommandType, Command]): (CommandType, Command) =
    try:
        let commandType = parseEnum[CommandType](cmd.toLowerAscii())
        let command = commands[commandType]
        return (commandType, command)
    except ValueError: 
        raise newException(ValueError, fmt"The command '{cmd}' does not exist.")

proc displayHelp(cq: Conquest, commands: Table[CommandType, Command]) = 
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

        let header = @["Name", "Type", "", "Description"]
        cq.writeLine(fmt"   {header[0]:<15} {header[1]:<8}{header[2]:<10} {header[3]}")
        cq.writeLine(fmt"   {'-'.repeat(15)} {'-'.repeat(18)} {'-'.repeat(20)}")
        
        for arg in command.arguments: 
            let requirement = if arg.isRequired: "(REQUIRED)" else: "(OPTIONAL)"
            cq.writeLine(fmt" * {arg.name:<15} {($arg.argumentType).toUpperAscii():<8}{requirement:<10} {arg.description}")

        cq.writeLine()

proc handleHelp(cq: Conquest, parsed: seq[string], commands: Table[CommandType, Command]) = 
    try: 
        # Try parsing the first argument passed to 'help' as a command
        let (commandType, command) = getCommandFromTable(parsed[1],  commands)
        cq.displayCommandHelp(command)
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

    let parsedArgs = parseAgentCommand(input)
    
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
            (commandType, command) = getCommandFromTable(parsedArgs[0], commands)
            payload = cq.packageArguments(command, parsedArgs)
        cq.createTask(commandType, $payload, fmt"Tasked agent to {command.description.toLowerAscii()}")

    except CatchableError: 
        cq.writeLine(fgRed, styleBright, fmt"[-] {getCurrentExceptionMsg()}" & "\n")
        return