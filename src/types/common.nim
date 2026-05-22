import ../common/toml/toml 

type    
    Uuid* = uint32
    Bytes* = seq[byte]
    Key* = array[32, byte]
    Iv* = array[12, byte]
    AuthenticationTag* = array[16, byte]
    KeyRC4* = array[16, byte]

type 
    KeyPair* = object 
        privateKey*: Key 
        publicKey*: Key

    Profile* = TomlTableRef

type 
    CommandType* {.size: sizeof(uint16).} = enum 
        CMD_EXIT = "exit"
        CMD_SELF_DESTRUCT = "self-destruct"
        CMD_SLEEP = "sleep"
        CMD_JITTER = "jitter"
        CMD_SLEEPMASK = "sleepmask"
        CMD_LINK = "link"
        CMD_UNLINK = "unlink"
        CMD_JOBS = "jobs"
        CMD_CANCEL = "cancel"
        CMD_SHELL = "shell"
        CMD_BOF = "bof"
        CMD_DOTNET = "dotnet"
        CMD_DLL ="dll"
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
        CMD_MAKE_TOKEN = "make-token"
        CMD_STEAL_TOKEN = "steal-token"
        CMD_USE_TOKEN = "use-token"
        CMD_REMOVE_TOKEN = "remove-token"
        CMD_REV2SELF = "rev2self"
        CMD_TOKEN_VAULT = "token-vault"
        CMD_TOKEN_INFO = "token-info"
        CMD_ENABLE_PRIV = "enable-privilege"
        CMD_DISABLE_PRIV = "disable-privilege"

    ModuleType* = enum 
        MODULE_SHELL = 1'u32 
        MODULE_BOF = 2'u32
        MODULE_DOTNET = 4'u32
        MODULE_FILESYSTEM = 8'u32 
        MODULE_FILETRANSFER = 16'u32
        MODULE_SCREENSHOT = 32'u32
        MODULE_PROCESS = 64'u32 
        MODULE_TOKEN = 128'u32
        MODULE_DLL = 256'u32

    SleepObfuscationTechnique* = enum 
        NONE = 0'u8
        EKKO = 1'u8 
        ZILEAN = 2'u8
        FOLIAGE = 3'u8
    
    DirectoryEntryFlags* = enum
        IS_DIR = 1'u8
        IS_HIDDEN = 2'u8
        IS_READONLY = 4'u8
        IS_ARCHIVE = 8'u8
        IS_SYSTEM = 16'u8
    
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
        LOG_COMMAND_SHORT = "[>] "

    ArgType* = enum 
        STRING = 0'u8
        INT = 1'u8
        BOOL = 2'u8 
        FILE = 3'u8 

    PacketType* = enum 
        MSG_TASK = 0'u8
        MSG_RESULT = 1'u8 
        MSG_REGISTER = 2'u8
        MSG_HEARTBEAT = 100'u8

    GuardrailType* = enum 
        GUARDRAIL_DOMAIN = 1'u8
        GUARDRAIL_IP = 2'u8
        GUARDRAIL_HOSTNAME = 4'u8

type 
    Guardrails* = ref object 
        guardrails*: uint32  
        domain*: string 
        ip*: string 
        hostname*: string

    WorkingHours* = ref object 
        enabled*: bool
        startHour*: int32 
        startMinute*: int32
        endHour*: int32
        endMinute*: int32

    SleepSettings* = ref object 
        sleepDelay*: uint32
        jitter*: uint32
        sleepTechnique*: SleepObfuscationTechnique
        spoofStack*: bool
        workingHours*: WorkingHours

# Shared types for client & server
when defined(client) or defined(server): 
    type 
        # Payload generation
        AgentType* {.size: sizeof(uint8).} = enum
            AGENT_MONARCH = "Monarch"

        PayloadType* {.size: sizeof(uint8).} = enum
            PAYLOAD_EXE = "Windows Executable (.exe)"
            PAYLOAD_SVC = "Windows Service Executable (.svc.exe)" 
            PAYLOAD_DLL = "Windows DLL (.dll)"
            # PAYLOAD_BIN = "Raw shellcode (.bin)"

        Architecture* {.size: sizeof(uint8).} = enum
            ARCH_X64 = "x64"

        ListenerType* {.size: sizeof(uint8).} = enum
            LISTENER_HTTP = "HTTP"
            LISTENER_SMB = "SMB"

        AgentBuildInformation* = ref object 
            listenerId*: string
            agentType*: AgentType
            arch*: Architecture
            payloadType*: PayloadType
            verbose*: bool
            sleepSettings*: SleepSettings
            guardrails*: Guardrails
            killDate*: int64
            modules*: uint32

        # Loot management
        LootItemType* = enum 
            DOWNLOAD = 0'u8 
            SCREENSHOT = 1'u8
            CREDENTIAL = 2'u8

        CredentialType* {.size: sizeof(uint16).} = enum 
            CRED_PASSWORD = "Password"
            CRED_NTLM = "NTLM Hash"
            CRED_OTHER = "Other"

        LootItem* = ref object
            lootId*: string
            agentId*: string
            host*: string
            timestamp*: int64
            note*: string
            itemType*: LootItemType
            path*: string
            remotePath*: string
            size*: int
            credType*: CredentialType
            username*: string
            value*: string
        