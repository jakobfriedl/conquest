import std/[paths, tables]
import strutils, strformat, sequtils, times
import ./websocket
import ../views/widgets/textarea
import ../utils/[utils, globals]
import ../../common/[sequence, crypto, utils, serialize]
import ../../types/[common, client, protocol]

proc parseInput*(input: string): seq[string] = 
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

proc parseArgument*(argument: Argument, value: string): TaskArg = 
    var arg: TaskArg
    arg.argType = cast[uint8](argument.argType)  
    case argument.argType:
    of INT: 
        let intValue = cast[uint32](parseUInt(value))
        arg.data = @[byte(intValue and 0xFF), byte((intValue shr 8) and 0xFF), byte((intValue shr 16) and 0xFF), byte((intValue shr 24) and 0xFF)]
    of BOOL: 
        arg.data = @[if value == "true": 1'u8 else: 0'u8]
    of STRING:
        arg.data = string.toBytes(value)
    of BINARY: 
        var packer = Packer.init() 
        let 
            fileName = cast[string](extractFilename(cast[Path](value)))
            fileContents = readFile(value)
        packer.addDataWithLengthPrefix(string.toBytes(fileName))
        packer.addDataWithLengthPrefix(string.toBytes(fileContents))
        arg.data = packer.pack() 
    return arg

proc getDefaultValue*(argument: Argument): string =
    case argument.argType:
    of STRING:
        return argument.strDefault
    of INT:
        return $argument.intDefault
    of BOOL:
        return $argument.boolDefault
    of BINARY:
        return argument.binDefault

proc parseArguments*(command: Command, arguments: seq[string]): seq[TaskArg] = 
    # Parse arguments into positional and optional (flag) arguments
    var flags = initTable[string, string]()
    var positional: seq[string] = @[]
    
    var i = 0
    while i < arguments.len():
        if arguments[i].startsWith("-"):
            flags[arguments[i]] = ""
            if i + 1 < arguments.len() and not arguments[i + 1].startsWith("-"):
                flags[arguments[i]] = arguments[i + 1]
                i += 2
            else:
                i += 1
        else:
            positional.add(arguments[i])
            i += 1
    
    # Validate flags
    let validFlags = command.arguments.filterIt(it.isFlag).mapIt(it.flag).toSeq()
    for flag, arg in flags:
        if flag notin validFlags:
            raise newException(CatchableError, fmt"Unknown flag: {flag}")
        if arg == "" and command.arguments.filterIt(it.flag == flag)[0].argType != BOOL: 
            raise newException(CatchableError, fmt"Value expected for flag: {flag}")

    # Map the command-line arguments to the arguments expected by the command 
    i = 0
    for arg in command.arguments:
        var taskArg: TaskArg
        taskArg.argType = cast[uint8](arg.argType)
        
        if arg.isFlag:
            if arg.flag in flags:
                let value = if arg.argType == BOOL: "true" elif flags[arg.flag] == "": "true" else: flags[arg.flag]
                taskArg = parseArgument(arg, value)
            else:
                if arg.isRequired:
                    raise newException(CatchableError, fmt"Missing required flag argument: {arg.name}")
                else:
                    # Use default value
                    taskArg = parseArgument(arg, getDefaultValue(arg))
        else:
            if i < positional.len():
                taskArg = parseArgument(arg, positional[i])
                i += 1
            else:
                if arg.isRequired:
                    raise newException(CatchableError, fmt"Missing required positional argument: {arg.name}")
                else:
                    # Use default value
                    taskArg = parseArgument(arg, getDefaultValue(arg))
        
        result.add(taskArg)
    
    # Handle extra positional args at the end of the command 
    let positionalArgs = command.arguments.filterIt(not it.isFlag)
    while i < positional.len() and positionalArgs.len() > 0:
        let lastArg = positionalArgs[^1]
        result.add(parseArgument(lastArg, positional[i]))
        i += 1

proc createTask*(agentId, listenerId: string, command: Command, arguments: seq[string], silent: bool): Task = 
    result.taskId = string.toUuid(generateUUID()) 
    result.listenerId = string.toUuid(listenerId)
    result.timestamp = uint32(now().toTime().toUnix())
    result.command = cast[uint16](parseEnum[CommandType](command.name)) 
    
    let taskArgs = command.parseArguments(arguments)
    result.argCount = uint8(taskArgs.len)
    result.args = taskArgs
    
    # Construct the header
    var taskHeader: Header
    taskHeader.magic = MAGIC
    taskHeader.version = VERSION 
    taskHeader.packetType = cast[uint8](MSG_TASK)
    
    taskHeader.flags = cast[uint16](FLAG_ENCRYPTED) or cast[uint16](FLAG_COMPRESSED)
    if silent: 
        taskHeader.flags = taskHeader.flags or cast[uint16](FLAG_SILENT)

    taskHeader.size = 0'u32
    taskHeader.agentId = string.toUuid(agentId)
    taskHeader.seqNr = nextSequence(taskHeader.agentId)
    taskHeader.iv = generateBytes(Iv)
    taskHeader.gmac = default(AuthenticationTag)
    result.header = taskHeader

# Wrapper functions for dispatching tasks to the agent
proc sendTask*(agentId, input: string, silent: bool = false) = 
    let args = input.parseInput()
    let command = cq.moduleManager.getCommand(args[0])
    let agent = cq.sessions.agents[agentId]
    let task = createTask(agentId, agent.listenerId, command, args[1..^1], silent)
    
    let message = ConsoleItem(
        timestamp: now().format("dd-MM-yyyy HH:mm:ss"),
        itemType: LOG_INFO,
        text: fmt"{command.message} ({Uuid.toString(task.taskId)})",
        highlight: false
    )

    cq.connection.sendAgentTask(agentId, task, $(message.getText))
    if cq.sessions.agents.hasKey(agentId) and not silent:
        cq.sessions.agents[agentId].console.textarea.addItem(message, agentId = agentId)
 
proc sendTask*(agentId, input, alias: string, silent: bool = false) = 
    let args = input.parseInput()
    let aliasArgs = alias.parseInput()
    let command = cq.moduleManager.getCommand(args[0])
    let aliasCommand = cq.moduleManager.getCommand(aliasArgs[0])
    let agent = cq.sessions.agents[agentId]
    let task = createTask(agentId, agent.listenerId, aliasCommand, aliasArgs[1..^1], silent)

    let message = ConsoleItem(
        timestamp: now().format("dd-MM-yyyy HH:mm:ss"),
        itemType: LOG_INFO,
        text: fmt"{command.message} ({Uuid.toString(task.taskId)})",
        highlight: false
    )

    cq.connection.sendAgentTask(agentId, task, $(message.getText))
    if cq.sessions.agents.hasKey(agentId) and not silent:
        cq.sessions.agents[agentId].console.textarea.addItem(message, agentId = agentId)