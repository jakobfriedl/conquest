import argparse, times, strformat, terminal, nanoid, tables, json, sequtils
import ./taskDispatcher
import ../types

#[
    Agent Argument parsing
]# 
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
    let commandType = parseEnum[CommandType](cmd.toLowerAscii())
    let command = commands[commandType]
    (commandType, command)
    
proc parseAgentCommand(input: string): seq[string] = 
    var i = 0
    while i < input.len:

        # Skip whitespaces/tabs
        while i < input.len and input[i] in {' ', '\t'}: 
            inc i
        if i >= input.len: 
            break
        
        var arg = ""
        if input[i] == '"':
            # Parse quoted argument
            inc i # Skip opening quote

            # Add parsed argument when quotation is closed
            while i < input.len and input[i] != '"': 
                arg.add(input[i]) 
                inc i
            
            if i < input.len: 
                inc i # Skip closing quote
        
        else:
            while i < input.len and input[i] notin {' ', '\t'}: 
                arg.add(input[i])
                inc i
        
        # Add argument to returned result
        if arg.len > 0: result.add(arg)


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
        cq.writeLine("Arguments:")

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

proc packageArguments(cq: Conquest, command: Command, arguments: seq[string]): JsonNode = 

    # Construct a JSON payload with argument names and values 
    result = newJObject()
    let parsedArgs = if arguments.len > 1: arguments[1..^1] else: @[] # Remove first element from sequence to only handle arguments

    # Check if the correct amount of parameters are passed
    if parsedArgs.len < command.arguments.filterIt(it.isRequired).len: 
        cq.displayCommandHelp(command)
        raise newException(ValueError, "Missing required arguments.")

    for i, argument in command.arguments: 
        
        # Argument provided - convert to the corresponding data type
        if i < parsedArgs.len:
            case argument.argumentType:
            of Int:
                result[argument.name] = %parseUInt(parsedArgs[i])
            of Binary: 
                # Read file into memory and convert it into a base64 string
                result[argument.name] = %""
            else:
                # The last optional argument is joined together
                # This is required for non-quoted input with infinite length, such as `shell mv arg1 arg2`
                if i == command.arguments.len - 1 and not argument.isRequired:
                    result[argument.name] = %parsedArgs[i..^1].join(" ")
                else:
                    result[argument.name] = %parsedArgs[i]
        
        # Argument not provided - set to empty string for optional args
        else:
            # If a required argument is not provided, display the help text
            if argument.isRequired:
                cq.displayCommandHelp(command)
                return
            else:
                result[argument.name] = %""

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
        let (commandType, command) = getCommandFromTable(parsedArgs[0], commands)
        let payload = cq.packageArguments(command, parsedArgs)
        cq.createTask(commandType, $payload, fmt"Tasked agent to {command.description.toLowerAscii()}")
    except ValueError as err: 
        cq.writeLine(fgRed, styleBright, fmt"[-] {err.msg}" & "\n")
        return