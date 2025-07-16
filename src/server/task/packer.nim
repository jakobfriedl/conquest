import strutils, json
import ../../types

proc packageArguments*(cq: Conquest, command: Command, arguments: seq[string]): JsonNode = 

    # Construct a JSON payload with argument names and values 
    result = newJObject()
    let parsedArgs = if arguments.len > 1: arguments[1..^1] else: @[] # Remove first element from sequence to only handle arguments

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
                raise newException(ValueError, "Missing required arguments.")
            else:
                result[argument.name] = %""