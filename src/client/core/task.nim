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
    of FILE: 
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
    of FILE:
        return argument.binDefault

proc parseArguments*(command: Command, arguments: seq[string]): seq[TaskArg] = 
    let flagArgs = command.arguments.filterIt(it.isFlag)
    let positionalArgDefs = command.arguments.filterIt(not it.isFlag)
    
    let hasCatchAll = positionalArgDefs.len() > 0 and positionalArgDefs[^1].nargs == -1
    
    # Pre-populate flags table with default values
    var flags = initTable[string, string]()
    for arg in flagArgs:
        flags[arg.flag] = if arg.argType == BOOL: "false" else: getDefaultValue(arg)
    
    var positional: seq[string] = @[]
    
    # Separate tokens into flags and positional arguments
    var i = 0
    while i < arguments.len():
        if arguments[i].startsWith("-"):
            let flag = arguments[i]
            let argDef = flagArgs.filterIt(it.flag == flag)
            
            if argDef.len() == 0:
                # Unknown flag — only valid if a catch-all arg exists
                if hasCatchAll:
                    positional.add(arguments[i])
                    i += 1
                else:
                    raise newException(CatchableError, fmt"Unknown flag: {flag}")
            elif argDef[0].nargs == 0:
                # Bool flag — no value
                flags[flag] = "true"
                i += 1
            else:
                # Flag with value
                if i + 1 < arguments.len():
                    flags[flag] = arguments[i + 1]
                    i += 2
                else:
                    raise newException(CatchableError, fmt"Value expected for flag: {flag}")
        else:
            positional.add(arguments[i])
            i += 1
    
    if not hasCatchAll and positional.len() > positionalArgDefs.len():
        raise newException(CatchableError, fmt"Too many positional arguments: expected {positionalArgDefs.len()}, got {positional.len()}")

    # Map positional and flag values onto argument definitions
    var positionalIndex = 0
    for arg in command.arguments:
        var taskArg: TaskArg
        taskArg.argType = cast[uint8](arg.argType)
        
        if arg.isFlag:
            if arg.isRequired and flags[arg.flag] == "":
                raise newException(CatchableError, fmt"Missing required flag: {arg.flag}")
            taskArg = parseArgument(arg, flags[arg.flag])
        else:
            case arg.nargs:
            of 0:
                taskArg = parseArgument(arg, "false")
            of 1:
                if positionalIndex < positional.len():
                    taskArg = parseArgument(arg, positional[positionalIndex])
                    positionalIndex += 1
                elif arg.isRequired:
                    raise newException(CatchableError, fmt"Missing required positional argument: {arg.name}")
                else:
                    taskArg = parseArgument(arg, getDefaultValue(arg))
            else:
                # nargs = -1: join all remaining positional tokens into one argument
                if positionalIndex < positional.len():
                    taskArg = parseArgument(arg, positional[positionalIndex..^1].join(" "))
                    positionalIndex = positional.len()
                elif arg.isRequired:
                    raise newException(CatchableError, fmt"Missing required positional argument: {arg.name}")
                else:
                    taskArg = parseArgument(arg, getDefaultValue(arg))
        
        result.add(taskArg)

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
    let 
        args = input.parseInput()
        command = cq.moduleManager.getCommand(args[0])
        agent = cq.sessions.agents[agentId]
        task = createTask(agentId, agent.listenerId, command, args[1..^1], silent)

    cq.connection.sendAgentTask(agentId, task, input, fmt"{command.message} ({Uuid.toString(task.taskId)})")
 
proc sendTask*(agentId, input, alias: string, silent: bool = false) = 
    let 
        args = input.parseInput()
        aliasArgs = alias.parseInput()
        command = cq.moduleManager.getCommand(args[0])
        aliasCommand = cq.moduleManager.getCommand(aliasArgs[0])
        agent = cq.sessions.agents[agentId]
        task = createTask(agentId, agent.listenerId, aliasCommand, aliasArgs[1..^1], silent)
        
    cq.connection.sendAgentTask(agentId, task, input, fmt"{command.message} ({Uuid.toString(task.taskId)})")