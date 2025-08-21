import tables, strformat
import ../common/types

# Import modules 
import 
    shell,
    sleep,
    filesystem,
    environment

type
    ModuleManager* = object 
        commandsByType*: Table[CommandType, Command]
        commandsByName*: Table[string, Command]

var manager: ModuleManager

proc registerCommands(commands: seq[Command]) {.discardable.} = 
    for cmd in commands: 
        manager.commandsByType[cmd.commandType] = cmd
        manager.commandsByName[cmd.name] = cmd

proc loadModules*() = 
    # Register all imported commands  
    registerCommands(shell.commands)
    registerCommands(sleep.commands)
    registerCommands(filesystem.commands)
    registerCommands(environment.commands)

proc getCommandByType*(cmdType: CommandType): Command = 
    return manager.commandsByType[cmdType]

proc getCommandByName*(cmdName: string): Command = 
    try:
        return manager.commandsByName[cmdName]
    except ValueError: 
        raise newException(ValueError, fmt"The command '{cmdName}' does not exist.")

proc getAvailableCommands*(): Table[string, Command] = 
    return manager.commandsByName