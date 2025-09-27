import std/paths
import strutils, sequtils, times, tables
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
    arg.argType = cast[uint8](argument.argumentType)  

    case argument.argumentType:

    of INT: 
        # Length: 4 bytes        
        let intValue = cast[uint32](parseUInt(value))
        arg.data = @[byte(intValue and 0xFF), byte((intValue shr 8) and 0xFF), byte((intValue shr 16) and 0xFF), byte((intValue shr 24) and 0xFF)]

    of SHORT: 
        # Length: 2 bytes 
        let shortValue = cast[uint16](parseUint(value))
        arg.data = @[byte(shortValue and 0xFF), byte((shortValue shr 8) and 0xFF)]

    of LONG: 
        # Length: 8 bytes
        var data = newSeq[byte](8)
        let longValue = cast[uint64](parseUInt(value))
        for i in 0..7:
            data[i] = byte((longValue shr (i * 8)) and 0xFF)
        arg.data = data

    of BOOL: 
        # Length: 1 byte
        if value == "true": 
            arg.data = @[1'u8] 
        elif value == "false": 
            arg.data = @[0'u8] 
        else: 
            raise newException(ValueError, "Invalid value for boolean argument.")

    of STRING:
        arg.data = string.toBytes(value)

    of BINARY: 
        # A binary data argument consists of the file name (without the path) and the file content in bytes, both prefixed with their length as a uint32
        var packer = Packer.init() 

        let fileName = cast[string](extractFilename(cast[Path](value)))
        packer.addDataWithLengthPrefix(string.toBytes(fileName))
        
        let fileContents = readFile(value)
        packer.addDataWithLengthPrefix(string.toBytes(fileContents))

        arg.data = packer.pack() 
    
    return arg

proc createTask*(cq: Conquest, agentId: string, command: Command, arguments: seq[string]): Task = 

    # Construct the task payload prefix
    var task: Task
    task.taskId = string.toUuid(generateUUID()) 
    task.listenerId = string.toUuid(cq.agents[agentId].listenerId)
    task.timestamp = uint32(now().toTime().toUnix())
    task.command = cast[uint16](command.commandType) 
    task.argCount = uint8(arguments.len)

    var taskArgs: seq[TaskArg]

    # Add the task arguments 
    if arguments.len() < command.arguments.filterIt(it.isRequired).len(): 
        raise newException(CatchableError, "Missing required argument.")

    for i, arg in arguments: 
        if i < command.arguments.len():
            taskArgs.add(parseArgument(command.arguments[i], arg))  
        else:
            # Optional arguments should ALWAYS be placed at the end of the command and take the same definition
            taskArgs.add(parseArgument(command.arguments[^1], arg))  

    task.args = taskArgs   

    # Construct the header
    var taskHeader: Header
    taskHeader.magic = MAGIC
    taskHeader.version = VERSION 
    taskHeader.packetType = cast[uint8](MSG_TASK)
    taskHeader.flags = cast[uint16](FLAG_ENCRYPTED)
    taskHeader.size = 0'u32
    taskHeader.agentId = string.toUuid(agentId)
    taskHeader.seqNr = nextSequence(taskHeader.agentId)
    taskHeader.iv = generateBytes(Iv) # Generate a random IV for AES-256 GCM
    taskHeader.gmac = default(AuthenticationTag)

    task.header = taskHeader

    # Return the task object for serialization
    return task