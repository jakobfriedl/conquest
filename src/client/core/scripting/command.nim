import nimpy 

type 
    ArgType* = enum 
        STRING = 0'u8
        INT = 1'u8
        BOOL = 4'u8 
        BINARY = 5'u8 

    Argument* = ref object 
        name*: string
        description*: string 
        isRequired*: bool 
        isFlag*: bool 
        flag*: string
        case argType*: ArgType
        of STRING:
            strDefault*: string 
        of INT: 
            intDefault*: int 
        of BOOL:
            boolDefault*: bool 
        of BINARY: 
            binDefault*: seq[byte]

    Command* = ref object of PyNimObjectExperimental
        name*: string 
        description*: string 
        example*: string
        message*: string 
        args*: seq[Argument]
        hasHandler*: bool
        handler*: PyObject 

    Module* = ref object of RootObj
        name*: string 
        description*: string
        path*: string 
        commands*: seq[Command]

proc newCommand*(name, description, example: string): Command = 
    return Command(
        name: name, 
        description: description,
        example: example,
        args: @[],
        hasHandler: false
    )

proc addArgString*(self: Command, name, description: string, required: bool = false, default: string = ""): Command {.exportpy.} = 
    self.args.add(Argument(
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
    self.args.add(Argument(
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
    self.args.add(Argument(
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
    self.args.add(Argument(
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
    self.args.add(Argument(
        name: name,
        description: description,
        isRequired: false,
        isFlag: true,
        flag: flag, 
        argType: BOOL,
        boolDefault: default
    ))
    return self

proc addArgFile*(self: Command, name, description: string, required: bool = true): Command {.exportpy.} = 
    self.args.add(Argument(
        name: name,
        description: description,
        isRequired: required, 
        isFlag: false,
        flag: "",
        argType: BINARY,
        binDefault: @[]
    ))
    return self

proc addFlagFile*(self: Command, flag, name, description: string, required: bool = true): Command {.exportpy.} = 
    self.args.add(Argument(
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
