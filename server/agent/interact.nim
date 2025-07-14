import argparse, times, strformat, terminal, nanoid, tables, json, sequtils
import ./taskDispatcher
import ../[types]

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

proc displayHelp(cq: Conquest, commands: Table[CommandType, Command]) = 
    cq.writeLine("Available commands:")
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
        for arg in command.arguments: 
            let requirement = if arg.isRequired: "REQUIRED" else: "OPTIONAL"
            cq.writeLine(fmt" * {arg.name:<15} {requirement}    {arg.description}")

        cq.writeLine()

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
            inc i # (Skip opening quote)

            while i < input.len and input[i] != '"': 
                # Add parsed argument when quotation is closed
                arg.add(input[i]) 
                inc i
            
            if i < input.len: 
                inc i # (Skip closing quote)
        
        else:
            while i < input.len and input[i] notin {' ', '\t'}: 
                arg.add(input[i])
                inc i
        
        # Add argument to returned result
        if arg.len > 0: result.add(arg)

proc handleAgentCommand*(cq: Conquest, input: string) = 

    let commands = initAgentCommands() 
    var 
        commandType: CommandType
        command: Command

    # Return if no command (or just whitespace) is entered
    if input.replace(" ", "").len == 0: return

    let date: string = now().format("dd-MM-yyyy HH:mm:ss")
    cq.writeLine(fgBlue, styleBright, fmt"[{date}] ", fgYellow, fmt"[{cq.interactAgent.name}] ", resetStyle, styleBright, input)

    # Split the user input, taking quotes into consideration 
    let parsed = parseAgentCommand(input)
    
    # Handle 'back' command
    if parsed[0] == "back": 
        return

    # Handle 'help' command 
    if parsed[0] == "help": 
        try: 
            # Try parsing the first argument passed to 'help' as a command
            commandType = parseEnum[CommandType](parsed[1].toLowerAscii())
            command = commands[commandType]
        except IndexDefect:
            # 'help' command is called without additional parameters
            cq.displayHelp(commands)
            return
        except ValueError: 
            # Command was not found
            cq.writeLine(fgRed, styleBright, fmt"[-] The command {parsed[1]} does not exist." & '\n')
            return 

        cq.displayCommandHelp(command)
        return

    # Following this, commands require actions on the agent and thus a task needs to be created
    # Determine the command used by checking the first positional argument
    try: 
        commandType = parseEnum[CommandType](parsed[0].toLowerAscii())
        command = commands[commandType]
    except ValueError: 
        cq.writeLine(fgRed, styleBright, "[-] Unknown command.\n")
        return 

    # TODO: Client/Server-side command specific actions (e.g. updating sleep, ...)

    # Construct a JSON payload with argument names and values 
    var payload = newJObject()
    let parsedArgs = if parsed.len > 1: parsed[1..^1] else: @[] # Remove first element from sequence to only handle arguments

    try: 
        for i, argument in command.arguments: 
            
            if i < parsedArgs.len:
                # Argument provided - convert to the corresponding data type
                case argument.argumentType:
                of Int:
                    payload[argument.name] = %parseInt(parsedArgs[i])
                of Binary: 
                    # Read file into memory and convert it into a base64 string
                    discard
                else:
                    payload[argument.name] = %parsedArgs[i]
            
            else:
                # Argument not provided - set to empty string for optional args
                # If a required argument is not provided, display the help text
                if argument.isRequired:
                    cq.displayCommandHelp(command)
                    return
                else:
                    payload[argument.name] = %""

    except CatchableError:
        cq.writeLine(fgRed, styleBright, "[-] Invalid syntax.\n")
        return

    # Task creation
    cq.createTask(commandType, $payload, fmt"Tasked agent to {command.description.toLowerAscii()}")