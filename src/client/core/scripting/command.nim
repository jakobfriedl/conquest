import nimpy 
import ../../../common/types

proc newCommand*(name, description, example: string): Command = 
    return Command(
        name: name, 
        description: description,
        example: example,
        arguments: @[],
        hasHandler: false
    )

proc addArgString*(self: Command, name, description: string, required: bool = false, default: string = ""): Command {.exportpy.} = 
    self.arguments.add(Argument(
        name: name,
        description: description,
        isRequired: required,
        isFlag: false,
        flag: "",
        argType: STRING,
        strDefault: default
    ))
    return self

proc addFlagString*(self: Command, flag, name, description: string, required: bool = false, default: string = ""): Command {.exportpy.} =
    self.arguments.add(Argument(
        name: name,
        description: description,
        isRequired: required,
        isFlag: true,
        flag: flag, 
        argType: STRING,
        strDefault: default
    ))
    return self

proc addArgInt*(self: Command, name, description: string, required: bool = false, default: int = 0): Command {.exportpy.} = 
    self.arguments.add(Argument(
        name: name,
        description: description,
        isRequired: required,
        isFlag: false,
        flag: "",
        argType: INT,
        intDefault: default
    ))
    return self

proc addFlagInt*(self: Command, flag, name, description: string, required: bool = false, default: int = 0): Command {.exportpy.} =
    self.arguments.add(Argument(
        name: name,
        description: description,
        isRequired: required,
        isFlag: true,
        flag: flag, 
        argType: INT,
        intDefault: default
    ))
    return self

proc addFlagBool*(self: Command, flag, name, description: string, default: bool = false): Command {.exportpy.} =
    self.arguments.add(Argument(
        name: name,
        description: description,
        isRequired: false,
        isFlag: true,
        flag: flag, 
        argType: BOOL,
        boolDefault: default
    ))
    return self

proc addArgFile*(self: Command, name, description: string, required: bool = false): Command {.exportpy.} = 
    self.arguments.add(Argument(
        name: name,
        description: description,
        isRequired: required, 
        isFlag: false,
        flag: "",
        argType: BINARY,
        binDefault: @[]
    ))
    return self

proc addFlagFile*(self: Command, flag, name, description: string, required: bool = false): Command {.exportpy.} = 
    self.arguments.add(Argument(
        name: name,
        description: description,
        isRequired: required, 
        isFlag: true,
        flag: flag,
        argType: BINARY,
        binDefault: @[]
    ))
    return self

proc setHandler(self: Command, handler: PyObject): Command {.exportpy.} = 
    if not handler.isNil and pyBuiltinsModule().callable(handler).to(bool):
        self.hasHandler = true
        self.handler = handler
    return self 
