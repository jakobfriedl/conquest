import ../../types

proc parseAgentCommand*(input: string): seq[string] = 
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
