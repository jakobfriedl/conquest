import imguin/[cimgui, glfw_opengl]
import nimgl/[opengl, glfw]
import nimpy, whisky, tables, std/options
import ./[common, event]

# Modules & commands
type 
    Argument* = ref object of PyNimObjectExperimental
        name*: string
        description*: string 
        isRequired*: bool 
        isFlag*: bool 
        flag*: string
        nargs*: int 
        case argType*: ArgType
        of STRING:
            strDefault*: string 
        of INT: 
            intDefault*: int 
        of BOOL:
            boolDefault*: bool 
        of FILE: 
            binDefault*: string

    Command* = ref object of PyNimObjectExperimental
        name*: string 
        description*: string 
        example*: string
        message*: string 
        mitre*: seq[string]
        arguments*: seq[Argument]
        hasHandler*: bool
        handler*: PyObject 

    Module* = ref object of RootObj
        name*: string 
        description*: string
        commands*: seq[Command]

# UI Components
const MAX_INPUT_LENGTH* = 16384 # Input needs to allow enough characters for long commands (e.g. Rubeus tickets, certficates, ...)

type 
    ConnectionModalComponent* = ref object of RootObj
        host*: array[256, char]
        defaultHost*: string 
        port*: uint16
        defaultPort*: int
        usernameInput*: array[256, char]
        passwordInput*: array[256, char] 
        username*: string
        password*: string
        errorMessage*: string

    WorkingHoursModalComponent* = ref object of RootObj
        workingHours*: WorkingHours

    KillDateModalComponent* = ref object of RootObj
        killDateTime*: ImPlotTime
        killDateLevel*: int32
        killDateHour*: int32
        killDateMinute*: int32
        killDateSecond*: int32

    DualListSelectionWidget*[T] = ref object of RootObj
        items*: array[2, seq[T]]
        selection*: array[2, ptr ImGuiSelectionBasicStorage]
        display*: proc(item: T): string
        compare*: proc(x, y: T): int
        tooltip*: proc(item: T): string

    ListenerModalComponent* = ref object of RootObj
        callbackHosts*: array[256 * 32, char]
        bindAddress*: array[256, char]
        bindPort*: uint16 
        pipe*: array[256, char]
        protocol*: int32
        protocols*: seq[string]

    EventlogComponent* = ref object of RootObj
        title*: string 
        showComponent*: ptr bool
        textarea*: TextareaWidget

    AgentModalComponent* = ref object of RootObj
        show*: bool
        listener*: int32 
        payloadType*: int32
        sleepDelay*: uint32
        jitter*: int32 
        sleepMask*: int32 
        spoofStack*: bool 
        killDateEnabled*: bool 
        killDate*: int64
        workingHoursEnabled*: bool
        workingHours*: WorkingHours
        verbose*: bool
        payloadTypes*: seq[string]  
        sleepMaskTechniques*: seq[string]
        moduleSelection*: DualListSelectionWidget[Module]
        buildLog*: TextareaWidget
        killDateModal*: KillDateModalComponent
        workingHoursModal*: WorkingHoursModalComponent

    ChatComponent* = ref object of RootObj 
        title*: string 
        showComponent*: ptr bool 
        textarea*: TextareaWidget
        inputBuffer*: array[MAX_INPUT_LENGTH, char]

    ListenersTableComponent* = ref object of RootObj
        title*: string 
        showComponent*: ptr bool
        listeners*: Table[string, UIListener]
        selection*: ptr ImGuiSelectionBasicStorage
        startListenerModal*: ListenerModalComponent
        generatePayloadModal*: AgentModalComponent

    ScriptManagerComponent* = ref object of RootObj
        title*: string 
        showComponent*: ptr bool
        scripts*: OrderedTable[string, tuple[active: bool, error: string]]
        modules*: Table[string, Module]
        groups*: OrderedTable[string, OrderedTable[string, Command]] 
        selection*: ptr ImGuiSelectionBasicStorage

    ProcessBrowserComponent* = ref object of RootObj
        title*: string 
        showComponent*: ptr bool
        agent*: int32
        selection*: uint32

    FileBrowserComponent* = ref object of RootObj
        title*: string 
        showComponent*: ptr bool
        agent*: int32
        selection*: string

    SessionsTableComponent* = ref object of RootObj
        title*: string 
        showComponent*: ptr bool
        agents*: Table[string, UIAgent]
        selection*: ptr ImGuiSelectionBasicStorage
        focusedConsole*: string 
        interact*: bool
    
    DownloadsComponent* = ref object of RootObj
        title*: string
        showComponent*: ptr bool
        items*: Table[string, tuple[item: LootItem, contents: string]]
        textarea*: TextareaWidget
        selectedLootId*: string

    ScreenshotTexture* = ref object 
        textureId*: GLuint
        data*: string
        width*: int 
        height*: int 

    ScreenshotsComponent* = ref object of RootObj
        title*: string
        showComponent*: ptr bool
        items*: Table[string, tuple[item: LootItem, texture: ScreenshotTexture]]
        selectedLootId*: string

    ConsoleItem* = ref object 
        itemType*: LogType
        timestamp*: string
        text*: string
        highlight*: bool

    ConsoleItems* = ref object
        items*: seq[ConsoleItem]
    
    TextareaWidget* = ref object of RootObj
        content*: ConsoleItems
        contentDisplayed*: ConsoleItems
        textSelect*: ptr TextSelect
        showTimestamps*: bool
        autoScroll*: bool

    ConsoleComponent* = ref object of RootObj
        agentId*: string
        showConsole*: bool
        inputBuffer*: array[MAX_INPUT_LENGTH, char]
        textarea*: TextareaWidget
        history*: seq[string]
        historyPosition*: int 
        currentInput*: string
        filter*: ptr ImGuiTextFilter
    
    ProcessInfo* = object 
        pid*: uint32
        ppid*: uint32 
        name*: string 
        user*: string
        session*: uint32
        children*: seq[uint32]

    Processes* = object
        rootProcesses*: seq[uint32] 
        processTable*: OrderedTable[uint32, ProcessInfo]
        timestamp*: int64

    DirectoryEntry* = object 
        name*: string 
        flags*: uint8
        size*: uint64
        lastWriteTime*: int64
        isLoaded*: bool
        children*: Option[OrderedTable[string, DirectoryEntry]]

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
        processes*: Option[Processes]
        filesystem*: Option[OrderedTable[string, DirectoryEntry]]
        workingDirectory*: Option[string]
        console*: ConsoleComponent 
        consoleTitle*: string
        hidden*: bool

    UIListener* = ref object
        listenerId*: string
        case listenerType*: ListenerType
        of LISTENER_HTTP: 
            hosts*: string
            address*: string
            port*: int
        of LISTENER_SMB: 
            pipe*: string

    WsConnection* = ref object
        ws*: WebSocket
        sessionKey*: Key
        user*: string

# Client context
type 
    Conquest* = ref object 
        sessions*: SessionsTableComponent
        listeners*: ListenersTableComponent
        chat*: ChatComponent
        eventlog*: EventlogComponent
        downloads*: DownloadsComponent
        screenshots*: ScreenshotsComponent
        processBrowser*: ProcessBrowserComponent
        fileBrowser*: FileBrowserComponent
        scriptManager*: ScriptManagerComponent
        connection*: WsConnection