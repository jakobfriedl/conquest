import strutils, strformat, times
import ../utils
import ../../common/[types, utils, crypto]

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
    
    var result: TaskArg
    result.argType = cast[uint8](argument.argumentType)  

    case argument.argumentType:

    of INT: 
        # Length: 4 bytes        
        let intValue = cast[uint32](parseUInt(value))
        result.data = @[byte(intValue and 0xFF), byte((intValue shr 8) and 0xFF), byte((intValue shr 16) and 0xFF), byte((intValue shr 24) and 0xFF)]

    of LONG: 
        # Length: 8 bytes
        var data = newSeq[byte](8)
        let intValue = cast[uint64](parseUInt(value))
        for i in 0..7:
            data[i] = byte((intValue shr (i * 8)) and 0xFF)
        result.data = data

    of BOOL: 
        # Length: 1 byte
        if value == "true": 
            result.data = @[1'u8] 
        elif value == "false": 
            result.data = @[0'u8] 
        else: 
            raise newException(ValueError, "Invalid value for boolean argument.")

    of STRING:
        result.data = cast[seq[byte]](value)

    of BINARY: 
        # Read file as binary stream 

        discard 
    
    return result

proc parseTask*(cq: Conquest, command: Command, arguments: seq[string]): Task = 

    # Construct the task payload prefix
    var task: Task
    task.taskId = uuidToUint32(generateUUID()) 
    task.listenerId = uuidToUint32(cq.interactAgent.listenerId)
    task.timestamp = uint32(now().toTime().toUnix())
    task.command = cast[uint16](command.commandType) 
    task.argCount = uint8(arguments.len)

    var taskArgs: seq[TaskArg]

    # Add the task arguments
    for i, arg in command.arguments:        
        if i < arguments.len: 
            taskArgs.add(parseArgument(arg, arguments[i]))
        else: 
            if arg.isRequired: 
                raise newException(ValueError, "Missing required argument.")
            else: 
                # Handle optional argument
                taskArgs.add(parseArgument(arg, ""))

    task.args = taskArgs   

    # Construct the header
    var taskHeader: Header
    taskHeader.magic = MAGIC
    taskHeader.version = VERSION 
    taskHeader.packetType = cast[uint8](MSG_TASK)
    taskHeader.flags = cast[uint16](FLAG_PLAINTEXT)
    taskHeader.size = 0'u32
    taskHeader.agentId = uuidtoUint32(cq.interactAgent.agentId)
    taskHeader.seqNr = 1'u64 # TODO: Implement sequence tracking
    taskHeader.iv = generateIV() # Generate a random IV for AES-256 GCM
    taskHeader.gmac = default(AuthenticationTag)

    task.header = taskHeader

    # Return the task object for serialization
    return task