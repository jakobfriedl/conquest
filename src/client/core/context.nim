import tables, strformat, strutils
import ../utils/appImGui
import ../views/widgets/[dualListSelection]
import ../views/modals/[startListener, configureKillDate, configureWorkingHours]
import ../../common/types

# Component type definitions

type 
    EventlogComponent* = ref object of RootObj
        title*: string 
        showComponent*: ptr bool
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
        showComponent*: ptr bool
        listeners*: Table[string, UIListener]
        selection*: ptr ImGuiSelectionBasicStorage
        startListenerModal*: ListenerModalComponent
        generatePayloadModal*: AgentModalComponent

    ModuleManagerComponent* = ref object of RootObj
        title*: string 
        showComponent*: ptr bool
        tempPath*: string
        modules*: Table[string, Module]
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
    
    DownloadsComponent* = ref object of RootObj
        title*: string
        showComponent*: ptr bool
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
        showComponent*: ptr bool
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
    fileBrowser*: FileBrowserComponent
    moduleManager*: ModuleManagerComponent
    connection*: WsConnection

var cq*: Conquest = new Conquest

proc parseModuleType*(moduleName: string): ModuleType =
    case moduleName.toLower()
    of "shell": return MODULE_SHELL
    of "bof": return MODULE_BOF
    of "dotnet": return MODULE_DOTNET
    of "filesystem": return MODULE_FILESYSTEM
    of "filetransfer": return MODULE_FILETRANSFER
    of "screenshot": return MODULE_SCREENSHOT
    of "systeminfo": return MODULE_SYSTEMINFO
    of "token": return MODULE_TOKEN
    else: discard

proc getModules*(component: ModuleManagerComponent, modules: uint32 = 0): seq[Module] = 
    for _, module in component.modules: 
        if not module.builtin and (modules == 0 or (modules and cast[uint32](parseModuleType(module.name))) != 0):
            result.add(module)

proc getModulesBuiltin*(component: ModuleManagerComponent): seq[Module] = 
    for _, module in component.modules: 
        if module.builtin:
            result.add(module)

proc getCommandsTable*(component: ModuleManagerComponent, modules: uint32 = 0): Table[string, Command] = 
    result = initTable[string, Command]() 
    let modules = component.getModulesBuiltin() & component.getModules(modules)
    for _, module in modules: 
        for cmd in module.commands: 
            result[cmd.name] = cmd

proc getCommands*(component: ModuleManagerComponent, modules: uint32 = 0): seq[Command] = 
    let modules = component.getModulesBuiltin() & component.getModules(modules)
    for _, module in modules: 
        result.add(module.commands)

proc getCommand*(component: ModuleManagerComponent, name: string): Command = 
    try: 
        let commands = component.getCommandsTable()
        return commands[name]
    except ValueError:
        raise newException(ValueError, fmt"The command '{name}' does not exist.")

proc getCommandGroups*(component: ModuleManagerComponent, modules: uint32 = 0): OrderedTable[string, seq[Command]] = 
    result = initOrderedTable[string, seq[Command]]() 
    let modules = component.getModulesBuiltin() & component.getModules(modules)

    for module in modules: 
        if not result.hasKey(module.group):
            result[module.group] = @[]
        result[module.group].add(module.commands)

proc cmp*(x, y: UIAgent): int =
    return cmp(x.firstCheckin, y.firstCheckin)
