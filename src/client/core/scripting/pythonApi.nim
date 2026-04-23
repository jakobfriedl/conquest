import tables, strformat, strutils, unicode
import ../[database, task, websocket]
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

proc addArgString*(self: Command, name, description: string, required: bool = false, default: string = "", nargs: int = 1): Command {.exportpy.} = 
    self.arguments.add(Argument(
        name: name,
        description: description,
        isRequired: required,
        isFlag: false,
        flag: "",
        argType: STRING,
        strDefault: default,
        nargs: nargs
    ))
    return self

proc addFlagString*(self: Command, flag, name, description: string, required: bool = false, default: string = "", nargs: int = 1): Command {.exportpy.} =
    self.arguments.add(Argument(
        name: name,
        description: description,
        isRequired: required,
        isFlag: true,
        flag: flag, 
        argType: STRING,
        strDefault: default,
        nargs: nargs
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
        intDefault: default,
        nargs: 1
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
        intDefault: default,
        nargs: 1
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
        boolDefault: default,
        nargs: 0
    ))
    return self

proc addArgFile*(self: Command, name, description: string, required: bool = false, default: string = ""): Command {.exportpy.} = 
    self.arguments.add(Argument(
        name: name,
        description: description,
        isRequired: required, 
        isFlag: false,
        flag: "",
        argType: FILE,
        binDefault: default,
        nargs: 1
    ))
    return self

proc addFlagFile*(self: Command, flag, name, description: string, required: bool = false, default: string = ""): Command {.exportpy.} = 
    self.arguments.add(Argument(
        name: name,
        description: description,
        isRequired: required, 
        isFlag: true,
        flag: flag,
        argType: FILE,
        binDefault: default,
        nargs: 1
    ))
    return self

proc setHandler*(self: Command, handler: PyObject): Command {.exportpy.} =          # handler(agentId: string, cmdline: string, args: seq[TaskArg])
    if not handler.isNil and pyBuiltinsModule().callable(handler).to(bool):
        self.hasHandler = true
        self.handler = handler
    return self 

proc setOutputHandler*(self: Command, handler: PyObject): Command {.exportpy.} = 
    if not handler.isNil and pyBuiltinsModule().callable(handler).to(bool):       # handler(agentId: string, output: string)
        self.hasOutputHandler = true
        self.outputHandler = handler
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

proc createModule*(name, description: string) {.exportpy.} =
    cq.scriptManager.modules[name] = Module(
        name: name,
        description: description,
        commands: @[]
    )

proc registerToGroup*(self: Command, group: string): Command {.exportpy.} = 
    if not cq.scriptManager.groups.hasKey(group):
        cq.scriptManager.groups[group] = initOrderedTable[string, Command]() 
    cq.scriptManager.groups[group][self.name] = self 
    return self

proc registerToModule*(self: Command, module: string): Command {.exportpy.} =
    if not cq.scriptManager.modules.hasKey(module):
        raise newException(CatchableError, fmt"Module not found: {module}.")
    cq.scriptManager.modules[module].commands.add(self)
    return self

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

# Pack object file and params for asynchronous BOF execution using the async-bof post-ex DLL
# Format: [objLen][objBytes][argsLen][argsBytes] 
proc async_bof_pack*(bof, params: string): string {.exportpy.} =
    var packer = Packer.init() 
    packer.addDataWithLengthPrefix(string.toBytes(readFile(bof)))
    packer.addDataWithLengthPrefix(if params.len > 0: Bytes.fromHex(string.toBytes(params)) else: @[])
    return Bytes.toHex(packer.pack() )
 
# Pack arguments into bytes
# https://sleep.dashnine.org/manual/pack.html
proc pack*(types: string, args: seq[PyObject]): seq[byte] {.exportpy.} = 
    if types.len() != args.len():
        raise newException(ValueError, "Invalid number of arguments.")
    
    var packer = Packer.init()
    for i, argType in types:
        let value = args[i]
        case argType:
        of 'b': # Binary data
            packer.addData(value.to(seq[byte]))
        
        of 'i': # Integer (4 bytes)
            packer.add(uint32(try: value.to(int) except: parseInt($value)))
        
        of 'I': # Integer little-endian (4 bytes) (equivalent for pack("I-", value))
            let intVal = uint32(try: value.to(int) except: parseInt($value))
            packer.addData(@[
                byte(intVal and 0xFF),
                byte((intVal shr 8) and 0xFF),
                byte((intVal shr 16) and 0xFF),
                byte((intVal shr 24) and 0xFF)
            ])
        
        of 's': # Short (2 bytes)
            packer.add(uint16(try: value.to(int) except: parseInt($value)))
        
        of 'z': # Null-terminated UTF-8
            let strData = string.toBytes($value) & @[0'u8]
            packer.addData(strData)
        
        of 'Z': # Null-terminated UTF-16 
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
            
            packer.addData(data & @[0'u8, 0'u8])
        
        else:
            raise newException(ValueError, "Unsupported type: " & argType)
    
    return packer.pack()     

proc debug_log*(message: string) {.exportpy.} = 
    echo ">> ", message

proc error*(agentId, message: string, cmdline: string = "") {.exportpy.} = 
    if cq.sessions.agents.hasKey(agentId):
        if cmdline != "":
            cq.sessions.agents[agentId].console.textarea.addItem(LOG_COMMAND, cmdline)
        cq.sessions.agents[agentId].console.textarea.addItem(LOG_ERROR, message)

proc warn*(agentId, message: string) {.exportpy.} = 
    if cq.sessions.agents.hasKey(agentId):
        cq.sessions.agents[agentId].console.textarea.addItem(LOG_WARNING, message)

proc info*(agentId, message: string) {.exportpy.} = 
    if cq.sessions.agents.hasKey(agentId):
        cq.sessions.agents[agentId].console.textarea.addItem(LOG_INFO, message)

proc success*(agentId, message: string) {.exportpy.} = 
    if cq.sessions.agents.hasKey(agentId):
        cq.sessions.agents[agentId].console.textarea.addItem(LOG_SUCCESS, message)

proc output*(agentId, message: string) {.exportpy.} = 
    if cq.sessions.agents.hasKey(agentId): 
        cq.sessions.agents[agentId].console.textarea.addItem(LOG_OUTPUT, message)

proc modules_root*(): string {.exportpy.} = 
    return CONQUEST_ROOT & "/data/modules"

proc resources_root*(): string {.exportpy.} = 
    return CONQUEST_ROOT & "/data/resources"

proc user*(): string {.exportpy.} = 
    return cq.connection.user

proc set_impersonation(agentId, token: string) {.exportpy.} = 
    if cq.sessions.agents.hasKey(agentId):
        cq.sessions.agents[agentId].impersonationToken = token
        cq.connection.sendImpersonationToken(agentId, token)

# Execute a command
proc execute_command*(agentId, command: string, silent: bool = false) {.exportpy.} =
    sendTask(agentId, command, silent)

# Execute an alias command string instead of the entered command
proc execute_alias*(agentId, command, alias: string, silent: bool = false) {.exportpy.} =
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

proc get_file*(args: seq[TaskArg], i: int = 0): tuple[name: string, data: seq[byte]] {.exportpy.} = 
    if i >= args.len():
        return ("", @[])
    var unpacker = Unpacker.init(Bytes.toString(args[i].data))
    result.name = unpacker.getDataWithLengthPrefix()                    # File name
    result.data = string.toBytes(unpacker.getDataWithLengthPrefix())    # File contents