import imguin/[cimgui, glfw_opengl]
import nimgl/[opengl, glfw]
import nimpy, whisky, tables, std/options
import ./common

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
        hasOutputHandler*: bool 
        outputHandler*: PyObject 

    Module* = ref object of RootObj
        name*: string 
        description*: string
        commands*: seq[Command]
    
# UI components
const MAX_INPUT_LENGTH* = 16384 # Input needs to allow enough characters for long commands (e.g. Rubeus tickets, certficates, ...)

type 
    # Widgets
    EdgeType* = enum
        EDGE_HTTP = "http"
        EDGE_SMB = "smb"

    GraphNode* = ref object
        pos*: tuple[x, y: float32]
        label*: string
        selected*: bool

    GraphEdge* = object
        srcId*: string
        dstId*: string
        edgeType*: EdgeType

    GraphWidget* = ref object
        nodes*: Table[string, GraphNode]
        edges*: seq[GraphEdge]
        scrollOffset*: tuple[x, y: float32]
        zoom*: float32
        draggingNodeId*: string
        textures*: array[5, GLuint]
        loaded*: bool

        # Settings
        showGrid*: bool
        showId*: bool
        showProcess*: bool
        showUser*: bool
        showHostname*: bool

    TextareaWidget* = ref object of RootObj
        content*: ConsoleItems
        textSelect*: ptr TextSelect
        showTimestamps*: bool
        autoScroll*: bool
        
    DualListSelectionWidget*[T] = ref object of RootObj
        items*: array[2, seq[T]]
        selection*: array[2, ptr ImGuiSelectionBasicStorage]
        display*: proc(item: T): string
        compare*: proc(x, y: T): int
        tooltip*: proc(item: T): string

    # Modals
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

    EncodingType* = enum
        ENCODING_NONE = "none"
        ENCODING_BASE64 = "base64"
        ENCODING_HEX = "hex"
        ENCODING_ROT = "rot"
        ENCODING_XOR = "xor"

    PlacementType* = enum
        PLACEMENT_HEADER = "header"
        PLACEMENT_QUERY = "query"
        PLACEMENT_BODY = "body"

    Encoding* = object
        encodingType*: EncodingType
        key*: int32
        urlSafe*: bool

    DataTransformation* = ref object
        placement*: PlacementType
        placementName*: array[256, char]
        encodings*: seq[Encoding]
        prepend*: array[MAX_INPUT_LENGTH, char]
        append*: array[MAX_INPUT_LENGTH, char]

    KeyValue* = object
        key*: array[256, char]
        value*: array[4096, char]

    ListenerModalComponent* = ref object of RootObj
        name*: array[256, char]
        protocol*: int32
        protocolLabels*: string
        encodingLabels*: string
        placementLabels*: string

        callbackHosts*: array[256 * 32, char]
        interfaces*: seq[string]
        bindAddress*: int32
        bindPort*: uint16
        pipe*: array[256, char]

        userAgentGET*: array[256 * 32, char]
        endpointsGET*: array[256 * 32, char]
        reqHeadersGET*: seq[KeyValue]
        queryParamsGET*: seq[KeyValue]
        heartbeatDataTransformation*: DataTransformation
        reqPreviewGET*: TextareaWidget

        respHeadersGET*: seq[KeyValue]
        tasksDataTransformation*: DataTransformation
        respPreviewGET*: TextareaWidget

        userAgentPOST*: array[256 * 32, char]
        endpointsPOST*: array[256 * 32, char]
        methods*: array[256 * 32, char]
        reqHeadersPOST*: seq[KeyValue]
        queryParamsPOST*: seq[KeyValue]
        resultDataTransformation*: DataTransformation
        reqPreviewPOST*: TextareaWidget

        respHeadersPOST*: seq[KeyValue]
        respBody*: array[MAX_INPUT_LENGTH, char]
        respPreviewPOST*: TextareaWidget

        previewCacheGETReq*: string
        previewCacheGETResp*: string
        previewCachePOSTReq*: string
        previewCachePOSTResp*: string
        previewSeed*: int
        profileSettingsOpen*: bool
        
        editingListener*: UIListener

    EventlogComponent* = ref object of RootObj
        title*: string 
        showComponent*: ptr bool
        textarea*: TextareaWidget

    PayloadModalComponent* = ref object of RootObj
        show*: bool
        agentTypes*: string
        architectures*: string
        payloadTypes*: string  
        sleepMaskTechniques*: string
        
        listener*: int32 
        agentType*: int32
        payloadType*: int32
        arch*: int32
        sleepDelay*: uint32
        jitter*: int32 
        sleepMask*: int32 
        spoofStack*: bool
        domainGuardrailEnabled*: bool 
        domainGuardrail*: array[MAX_INPUT_LENGTH, char]
        ipGuardrailEnabled*: bool 
        ipGuardrail*: array[MAX_INPUT_LENGTH, char]
        hostGuardrailEnabled*: bool 
        hostGuardrail*: array[MAX_INPUT_LENGTH, char]
        killDateEnabled*: bool 
        killDate*: int64
        selfDelete*: bool
        workingHoursEnabled*: bool
        workingHours*: WorkingHours
        verbose*: bool

        moduleSelection*: DualListSelectionWidget[Module]
        configJson*: string
        configPreview*: TextareaWidget
        buildLog*: TextareaWidget
        killDateModal*: KillDateModalComponent
        workingHoursModal*: WorkingHoursModalComponent
        resetTab*: bool

    CredentialModalComponent* = ref object of RootObj
        show*: bool
        credType*: int32
        host*: array[256, char]
        username*: array[256, char]
        value*: array[512, char]
        note*: array[MAX_INPUT_LENGTH, char]
        credTypes*: string
        editingItem*: LootItem

    NoteModalComponent* = ref object of RootObj
        show*: bool 
        note*: array[MAX_INPUT_LENGTH, char]
        editingItem*: LootItem

    # Windows/Views
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
        generatePayloadModal*: PayloadModalComponent
        profilePreview*: TextareaWidget
        showProfilePreview*: bool

    ScriptManagerComponent* = ref object of RootObj
        title*: string 
        showComponent*: ptr bool
        scripts*: OrderedTable[string, tuple[active: bool, error: string, commands: seq[tuple[group: string, name: string]]]]
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

    SessionsComponent* = ref object of RootObj
        agents*:         Table[string, UIAgent]
        selection*:      ptr ImGuiSelectionBasicStorage
        focusedConsole*: string
        interact*:       bool
        tableTitle*:     string
        showTable*:      ptr bool
        graphTitle*:     string
        showGraph*:      ptr bool
        graph*:          GraphWidget

    # Loot 
    DownloadsComponent* = ref object of RootObj
        title*: string
        showComponent*: ptr bool
        items*: Table[string, tuple[item: LootItem, contents: string]]
        textarea*: TextareaWidget
        selectedLootId*: string
        noteModal*: NoteModalComponent

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
        noteModal*: NoteModalComponent

    CredentialsComponent* = ref object of RootObj
        title*: string
        showComponent*: ptr bool
        items*: Table[string, LootItem]
        selection*: ptr ImGuiSelectionBasicStorage
        credentialModal*: CredentialModalComponent

    # Console 
    ConsoleItem* = ref object
        itemType*: LogType
        timestamp*: string
        text*: string
        highlight*: bool
        segments*: seq[tuple[text: string, color: ImVec4]]

    ConsoleItems* = ref object
        items*: seq[ConsoleItem]

    ConsoleComponent* = ref object of RootObj
        agentId*: string
        showConsole*: bool
        inputBuffer*: array[MAX_INPUT_LENGTH, char]
        textarea*: TextareaWidget
        history*: seq[string]
        historyPosition*: int
        currentInput*: string

        # Tab auto-completion
        autocompleteMatches*: seq[string]
        autocompleteIndex*: int

        # Search functionality
        searchBuffer*: array[256, char]
        searchActive*: bool
        searchFocus*: bool
        searchRegex*: bool
        searchMatchCase*: bool
        searchPrevQuery*: string
        searchMatches*: seq[tuple[line: int, a: int, b: int]]  
        currentMatch*: int
        scrollToCurrentMatch*: bool

    # Other
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
        modules*: uint32
        firstCheckin*: int64
        latestCheckin*: int64
        processes*: Option[Processes]
        filesystem*: Option[OrderedTable[string, DirectoryEntry]]
        workingDirectory*: Option[string]
        console*: ConsoleComponent 
        consoleTitle*: string
        hidden*: bool
        parentId*: string

    UIListener* = ref object
        listenerId*: string
        name*: string
        timestamp*: int64
        case listenerType*: ListenerType
        of LISTENER_HTTP: 
            hosts*: string
            address*: string
            port*: int
            profile*: string
        of LISTENER_SMB: 
            pipe*: string

    WsConnection* = ref object
        ws*: WebSocket
        sessionKey*: Key
        user*: string

# Client context
type 
    Conquest* = ref object
        profile*: Profile
        sessions*: SessionsComponent
        listeners*: ListenersTableComponent
        chat*: ChatComponent
        eventlog*: EventlogComponent
        downloads*: DownloadsComponent
        screenshots*: ScreenshotsComponent
        credentials*: CredentialsComponent
        processBrowser*: ProcessBrowserComponent
        fileBrowser*: FileBrowserComponent
        scriptManager*: ScriptManagerComponent
        connection*: WsConnection