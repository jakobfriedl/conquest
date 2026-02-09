import tables, base64, strformat, strutils, os, unicode
import ../[database, task]
import ../../utils/globals
import ../../views/widgets/textarea
import ../../../common/[utils, serialize]
import ../../../types/[common, client, protocol]

#[
    Conquest Python API
    - exports functions that can be used in the module scripts
    - file operations
    - argument parsing 
    - command execution 
    
    References: 
    - https://github.com/Adaptix-Framework/AdaptixC2/blob/main/AdaptixClient/Headers/Client/AxScript/BridgeApp.h
    - https://hstechdocs.helpsystems.com/manuals/cobaltstrike/current/userguide/content/topics_aggressor-scripts/as-resources_functions.htm 
]#

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

proc addArgFile*(self: Command, name, description: string, required: bool = false, default: string = ""): Command {.exportpy.} = 
    self.arguments.add(Argument(
        name: name,
        description: description,
        isRequired: required, 
        isFlag: false,
        flag: "",
        argType: BINARY,
        binDefault: default
    ))
    return self

proc addFlagFile*(self: Command, flag, name, description: string, required: bool = false, default: string = ""): Command {.exportpy.} = 
    self.arguments.add(Argument(
        name: name,
        description: description,
        isRequired: required, 
        isFlag: true,
        flag: flag,
        argType: BINARY,
        binDefault: default
    ))
    return self

proc setHandler(self: Command, handler: PyObject): Command {.exportpy.} = 
    if not handler.isNil and pyBuiltinsModule().callable(handler).to(bool):
        self.hasHandler = true
        self.handler = handler
    return self 

proc createCommand*(name, description, example, message: string, mitre: seq[string] = @[]): Command {.exportpy.} = 
    return Command(
        name: name, 
        description: description,
        example: example,
        message: message,
        mitre: mitre,
        arguments: @[],
        hasHandler: false
    )

proc registerModule*(name, description, group: string, commands: seq[Command], builtin: bool = false) {.exportpy.} = 
    # Store module in database 
    if not dbModuleExists(name):
        discard dbStoreModule(name, cq.moduleManager.tempPath)

    cq.moduleManager.modules[name] = Module(
        name: name, 
        description: description, 
        path: cq.moduleManager.tempPath,
        group: group,
        builtin: builtin,
        commands: commands
    )

# Parse and handle BOF arguments
# References:
# - https://hstechdocs.helpsystems.com/manuals/cobaltstrike/current/userguide/content/topics_aggressor-scripts/as-resources_functions.htm#bof_pack
# - https://github.com/trustedsec/COFFLoader/blob/main/beacon_generate.py  
# Type format:
# - b: Binary data with length-prefix
# - i: 4-byte integer
# - s: 2-byte short integer
# - z: Null-terminated string with length-prefix (UTF-8)
# - Z: Null-terminated wide-char string with length-prefix (UTF-16)
proc bof_pack*(types: string, args: seq[PyObject]): string {.exportpy.} = 
    if types.len() != args.len():
        raise newException(ValueError, "Invalid number of arguments.")
    
    var packer = Packer.init()
    for i, argType in types:
        let value = args[i]
        case argType:
        of 'b': # Binary data (raw bytes with 4-byte length prefix)
            packer.addDataWithLengthPrefix(value.to(seq[byte]))
        
        of 'i': # Integer (4 bytes)
            packer.add(uint32(try: value.to(int) except: parseInt($value)))
        
        of 's': # Short (2 bytes)
            packer.add(uint16(try: value.to(int) except: parseInt($value)))
        
        of 'z': # Null-terminated UTF-8 (with 4-byte prefixed length)
            let data = string.toBytes($value) & @[0'u8]
            packer.addDataWithLengthPrefix(data)
        
        of 'Z': # Null-terminated UTF-16 (with 4-byte prefixed length)
            var data: seq[byte] = @[]
            for r in ($value).runes:
                let c = uint32(r)
                if c <= 0xFFFF:
                    data.add(byte(c and 0xFF))
                    data.add(byte(c shr 8))
                else:
                    let adj = c - 0x10000
                    let lead = uint16((adj shr 10) + 0xD800)
                    let trail = uint16((adj and 0x3FF) + 0xDC00)
                    data.add(byte(lead and 0xFF)); data.add(byte(lead shr 8))
                    data.add(byte(trail and 0xFF)); data.add(byte(trail shr 8))
            
            packer.addDataWithLengthPrefix(data & @[0'u8, 0'u8])
        
        else:
            raise newException(ValueError, "Unsupported type: " & argType)
    
    let data = packer.pack()
    return Bytes.toHex(uint32.toBytes(uint32(data.len())) & data)

proc log(message: string) {.exportpy.} = 
    echo ">> ", message

proc error(agentId, cmdline, message: string) {.exportpy.} = 
    if cq.sessions.agents.hasKey(agentId):
        cq.sessions.agents[agentId].console.textarea.addItem(LOG_COMMAND, cmdline)
        cq.sessions.agents[agentId].console.textarea.addItem(LOG_ERROR, message)

proc modules_root(): string {.exportpy.} = 
    return CONQUEST_ROOT & "/data/modules"

proc user(): string {.exportpy.} = 
    return cq.connection.user

# Execute a command 
proc execute_command(agentId, command: string, silent: bool = false) {.exportpy.} = 
    sendTask(agentId, command, silent)

# Takes a command string as the argument that is executed instead 
proc execute_alias(agentId, command, alias: string, silent: bool = false) {.exportpy.} =
    sendTask(agentId, command, alias, silent)

proc get_string*(args: seq[TaskArg], i: int = 0): string {.exportpy.} = 
    if i >= args.len(): 
        return ""
    return Bytes.toString(args[i].data)

proc get_int*(args: seq[TaskArg], i: int = 0): int {.exportpy.} = 
    if i >= args.len(): 
        return 0
    return int(Bytes.toUint32(args[i].data))

proc get_bool*(args: seq[TaskArg], i: int = 0): bool {.exportpy.} = 
    if i >= args.len(): 
        return false
    return cast[bool](args[i].data[0])