import tables, strformat
import imguin/[cimgui, glfw_opengl]
import ../utils/appImGui
import ../views/widgets/[dualListSelection, textarea]
import ../views/modals/[startListener, configureKillDate, configureWorkingHours]
import ../../common/types

# Component type definitions
const MAX_INPUT_LENGTH* = 4096 # Input needs to allow enough characters for long commands (e.g. Rubeus tickets)

type 
    EventlogComponent* = ref object of RootObj
        title*: string 
        textarea*: TextareaWidget

    AgentModalComponent* = ref object of RootObj
            show*: bool
            listener*: int32 
            sleepDelay*: uint32
            jitter*: int32 
            sleepMask*: int32 
            spoofStack*: bool 
            killDateEnabled*: bool 
            killDate*: int64
            workingHoursEnabled*: bool
            workingHours*: WorkingHours
            verbose*: bool
            sleepMaskTechniques*: seq[string]
            moduleSelection*: DualListSelectionWidget[Module]
            buildLog*: TextareaWidget
            killDateModal*: KillDateModalComponent
            workingHoursModal*: WorkingHoursModalComponent

    ListenersTableComponent* = ref object of RootObj
        title*: string 
        listeners*: Table[string, UIListener]
        selection*: ptr ImGuiSelectionBasicStorage
        startListenerModal*: ListenerModalComponent
        generatePayloadModal*: AgentModalComponent

    ModuleManagerComponent* = ref object of RootObj
        title*: string 
        tempPath*: string
        modules*: Table[string, Module]
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
    connection*: WsConnection

var cq*: Conquest = new Conquest

proc getModules*(component: ModuleManagerComponent, modules: uint32 = 0): seq[Module] = 
    for _, module in component.modules: 
        if not module.builtin: 
            result.add(module)

proc getCommandsTable*(component: ModuleManagerComponent, modules: uint32 = 0): Table[string, Command] = 
    result = initTable[string, Command]() 
    for _, module in component.modules: 
        for cmd in module.commands: 
            result[cmd.name] = cmd

proc getCommands*(component: ModuleManagerComponent, modules: uint32 = 0): seq[Command] = 
    for _, module in component.modules: 
        result.add(module.commands)

proc getCommand*(component: ModuleManagerComponent, name: string): Command = 
    try: 
        let commands = component.getCommandsTable()
        return commands[name]
    except ValueError:
        raise newException(ValueError, fmt"The command '{name}' does not exist.")