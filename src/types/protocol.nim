import ./common

const   
    MAGIC* = 0x514E3043'u32     # Magic value: C0NQ
    VERSION* = 1'u8             # Version 1
    HEADER_SIZE* = 48'u8        # 48 bytes fixed packet header size

type
    HeaderFlags* = enum 
        FLAG_PLAINTEXT = 0'u16
        FLAG_ENCRYPTED = 1'u16
        FLAG_COMPRESSED = 2'u16
        FLAG_SILENT = 4'u16

    StatusType* = enum 
        STATUS_COMPLETED = 0'u8
        STATUS_FAILED = 1'u8
        STATUS_STARTED = 2'u8
        STATUS_IN_PROGRESS = 3'u8
        STATUS_CANCELLED = 4'u8

    ResultType* = enum 
        RESULT_NO_OUTPUT = 0'u8
        RESULT_STRING = 1'u8        # Agent console output
        RESULT_BINARY = 2'u8        # Binary data structures or files

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
        data*: seq[byte]            # variable length data (for variable data types (STRING, FILE), the first 4 bytes indicate data length)

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

    Heartbeat* = object 
        header*: Header            # [48 bytes ] fixed header
        listenerId*: Uuid          # [4 bytes  ] listener id
        timestamp*: uint32         # [4 bytes  ] unix timestamp

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
