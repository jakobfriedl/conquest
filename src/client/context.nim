import tables
import imguin/[cimgui, glfw_opengl]
import ./utils/appImGui
import ./views/widgets/textarea
import ./views/modals/[startListener, generatePayload]
import ../common/types

# Component type definitions
const MAX_INPUT_LENGTH* = 4096 # Input needs to allow enough characters for long commands (e.g. Rubeus tickets)

type 
    EventlogComponent* = ref object of RootObj
        title*: string 
        textarea*: TextareaWidget

    ListenersTableComponent* = ref object of RootObj
        title*: string 
        listeners*: Table[string, UIListener]
        selection*: ptr ImGuiSelectionBasicStorage
        startListenerModal*: ListenerModalComponent
        generatePayloadModal*: AgentModalComponent

    ModuleManagerComponent* = ref object of RootObj
        title*: string 
        tempModule*: tuple[name, description, path: string, commandCount: int]
        modules*: Table[string, tuple[name, description, path: string, commandCount: int]]
        selection*: ptr ImGuiSelectionBasicStorage

    Processes* = object
        rootProcesses*: seq[uint32] 
        processTable*: OrderedTable[uint32, ProcessInfo]
        timestamp*: int64

    ProcessBrowserComponent* = ref object of RootObj
        title*: string 
        agent*: int32
        processes*: Table[string, Processes]
        selection*: uint32
        autoUpdate*: bool

    SessionsTableComponent* = ref object of RootObj
        title*: string 
        agents*: Table[string, UIAgent]
        selection*: ptr ImGuiSelectionBasicStorage
        consoles*: ptr Table[string, ConsoleComponent]
        focusedConsole*: string 

    ConsoleComponent* = ref object of RootObj
        agent*: UIAgent
        showConsole*: bool
        inputBuffer*: array[MAX_INPUT_LENGTH, char]
        console*: TextareaWidget
        history*: seq[string]
        historyPosition*: int 
        currentInput*: string
        filter*: ptr ImGuiTextFilter
    
    DownloadsComponent* = ref object of RootObj
        title*: string
        items*: seq[LootItem]
        contents*: Table[string, string]
        textarea*: TextareaWidget
        selectedIndex*: int

    ScreenshotTexture* = ref object 
        textureId*: GLuint
        data*: string
        width*: int 
        height*: int 

    ScreenshotsComponent* = ref object of RootObj
        title*: string
        items*: seq[LootItem]
        selectedIndex*: int
        textures*: Table[string, ScreenshotTexture]

# Global client context structure
type Conquest* = ref object 
    sessions*: SessionsTableComponent
    listeners*: ListenersTableComponent
    eventlog*: EventlogComponent
    downloads*: DownloadsComponent
    screenshots*: ScreenshotsComponent
    processBrowser*: ProcessBrowserComponent
    moduleManager*: ModuleManagerComponent
    consoles*: Table[string, ConsoleComponent]

var cq*: Conquest = new Conquest
