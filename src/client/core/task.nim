import std/[paths, tables]
import strutils, strformat, sequtils, times
import ./[websocket, context]
import ../views/widgets/textarea
import ../../common/[types, sequence, crypto, utils, serialize]

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

proc parseArguments*(command: Command, arguments: seq[string]): seq[TaskArg] = 
    # Parse input into flags and positional args
    var flags = initTable[string, string]()
    var positional: seq[string] = @[]
    
    var i = 0
    while i < arguments.len():
        if arguments[i].startsWith("-"):
            flags[arguments[i]] = ""  # Mark flag as present
            # Check if next arg is a value (not another flag)
            if i + 1 < arguments.len() and not arguments[i + 1].startsWith("-"):
                flags[arguments[i]] = arguments[i + 1]
                i += 2
            else:
                i += 1
        else:
            positional.add(arguments[i])
            i += 1
        
    # Map the cli arguments to the arguments expected by the command 
    i = 0
    for arg in command.arguments:
        if arg.isFlag:
            if arg.flag in flags:
                let value = if arg.argType == BOOL: "true" elif flags[arg.flag] == "": "true" else: flags[arg.flag]
                result.add(parseArgument(arg, value))
            elif arg.isRequired:
                raise newException(CatchableError, fmt"Missing required flag argument: {arg.name}")
            elif arg.argType == BOOL:
                result.add(parseArgument(arg, $arg.boolDefault))
        else:
            if i < positional.len():
                result.add(parseArgument(arg, positional[i]))
                i += 1
            elif arg.isRequired:
                raise newException(CatchableError, fmt"Missing required positional argument: {arg.name}")
    
    # Handle extra positional args at the end of the command 
    while i < positional.len() and command.arguments.len() > 0:
        let lastArg = command.arguments.filterIt(not it.isFlag)[^1]
        result.add(parseArgument(lastArg, positional[i]))
        i += 1

proc createTask*(agentId, listenerId: string, command: Command, arguments: seq[string]): Task = 
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
    taskHeader.flags = cast[uint16](FLAG_ENCRYPTED)
    taskHeader.size = 0'u32
    taskHeader.agentId = string.toUuid(agentId)
    taskHeader.seqNr = nextSequence(taskHeader.agentId)
    taskHeader.iv = generateBytes(Iv)
    taskHeader.gmac = default(AuthenticationTag)
    result.header = taskHeader

# Wrapper functions for dispatching tasks to the agent
proc sendTask*(agentId, input: string) = 
    let args = input.parseInput()
    let command = cq.moduleManager.getCommand(args[0])
    let agent = cq.sessions.agents[agentId]
    let task = createTask(agentId, agent.listenerId, command, args[1..^1])
    
    cq.connection.sendAgentTask(agentId, input, task)
    if cq.consoles.hasKey(agentId):
        cq.consoles[agentId].console.addItem(LOG_INFO, fmt"{command.message} ({Uuid.toString(task.taskId)})")
 
proc sendTask*(agentId, input, alias: string) = 
    let args = input.parseInput()
    let aliasArgs = alias.parseInput()
    let command = cq.moduleManager.getCommand(args[0])
    let aliasCommand = cq.moduleManager.getCommand(aliasArgs[0])
    let agent = cq.sessions.agents[agentId]
    let task = createTask(agentId, agent.listenerId, aliasCommand, aliasArgs[1..^1])

    cq.connection.sendAgentTask(agentId, input, task)
    if cq.consoles.hasKey(agentId):
        cq.consoles[agentId].console.addItem(LOG_INFO, fmt"{command.message} ({Uuid.toString(task.taskId)})")
