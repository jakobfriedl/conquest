import ./command

#[
    Python API
    - export functions that can be used in the scripts
    - use a global context structure to return agents, listeners, etc. (maybe only for UI)
    - file operations
    - argument parsing 
    - command execution 
    
    References: https://github.com/Adaptix-Framework/AdaptixC2/blob/main/AdaptixClient/Headers/Client/AxScript/BridgeApp.h
]#

proc createCommand*(name, description, example: string): Command {.exportpy.} = 
    return newCommand(name, description, example)

proc registerModule*(name, description: string, commands: seq[Command]) {.exportpy.} = 
    cq.moduleManager.tempModule.name = name 
    cq.moduleManager.tempModule.description = description
    cq.moduleManager.tempModule.commandCount = commands.len() 

    # Store module in database 

    cq.moduleManager.modules.add(cq.moduleManager.tempModule)
    
proc bofPack() = 

    # Parses and handles BOF arguments

    discard 

proc message(message: string) {.exportpy.} = 
    echo ">> ", message

proc execCommand() = 
    discard

proc execAlias() = 

    # Takes a command string as the argument that is executed instead 

    discard 

proc fileExists() = 
    discard 

proc scriptDir() = 
    discard