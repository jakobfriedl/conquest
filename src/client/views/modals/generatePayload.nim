import strutils, sequtils, times
import imguin/[cimgui, glfw_opengl, simple]
import ../../utils/[appImGui, colors]
import ../../../common/[types, profile, utils]
import ../../../modules/manager
import ../widgets/dualListSelection

type 
    AgentModalComponent* = ref object of RootObj
        listener: int32 
        sleepDelay: uint32 
        sleepMask: int32 
        spoofStack: bool 
        sleepMaskTechniques: seq[string]
        moduleSelection: DualListSelectionComponent[Module]
        buildLog: ConsoleItems


proc AgentModal*(): AgentModalComponent =
    result = new AgentModalComponent
    result.listener = 0
    result.sleepDelay = 5
    result.sleepMask = 0
    result.spoofStack = false

    for technique in SleepObfuscationTechnique.low .. SleepObfuscationTechnique.high:
        result.sleepMaskTechniques.add($technique)

    let modules = getModules()
    proc moduleName(module: Module): string = 
        return module.name
    proc moduleDesc(module: Module): string = 
        result = module.description & "\nModule commands:\n"
        for cmd in module.commands: 
            result &= " - " & cmd.name & "\n"
    proc compareModules(x, y: Module): int = 
        return cmp(x.moduleType, y.moduleType)

    result.moduleSelection = DualListSelection(modules, moduleName, compareModules, moduleDesc)

    result.buildlog = new ConsoleItems
    result.buildLog.items = @[]

proc resetModalValues*(component: AgentModalComponent) = 
    component.listener = 0
    component.sleepDelay = 5
    component.sleepMask = 0
    component.spoofStack = false 
    component.moduleSelection.reset()
    component.buildLog.items = @[]

proc addBuildlogItem*(component: AgentModalComponent, itemType: LogType, data: string, timestamp: string = now().format("dd-MM-yyyy HH:mm:ss")) = 
    for line in data.split("\n"): 
        component.buildLog.items.add(ConsoleItem(
            timestamp: timestamp,
            itemType: itemType,
            text: line
        ))

proc print(component: AgentModalComponent, item: ConsoleItem) =         
    case item.itemType:
    of LOG_INFO, LOG_INFO_SHORT: 
        igTextColored(CONSOLE_INFO, $item.itemType)
    of LOG_ERROR, LOG_ERROR_SHORT: 
        igTextColored(CONSOLE_ERROR, $item.itemType)
    of LOG_SUCCESS, LOG_SUCCESS_SHORT: 
        igTextColored(CONSOLE_SUCCESS, $item.itemType)
    of LOG_WARNING, LOG_WARNING_SHORT: 
        igTextColored(CONSOLE_WARNING, $item.itemType)
    of LOG_COMMAND: 
        igTextColored(CONSOLE_COMMAND, $item.itemType)
    of LOG_OUTPUT: 
        igTextColored(vec4(0.0f, 0.0f, 0.0f, 0.0f), $item.itemType)

    igSameLine(0.0f, 0.0f)
    igTextUnformatted(item.text.cstring, nil)

proc draw*(component: AgentModalComponent, listeners: seq[UIListener]): AgentBuildInformation =

    let textSpacing = igGetStyle().ItemSpacing.x    
    
    # Center modal
    let vp = igGetMainViewport()
    var center: ImVec2
    ImGuiViewport_GetCenter(addr center, vp)
    igSetNextWindowPos(center, ImGuiCond_Appearing.int32, vec2(0.5f, 0.5f))

    let modalWidth = max(500.0f, vp.Size.x * 0.25)
    igSetNextWindowSize(vec2(modalWidth, 0.0f), ImGuiCond_Always.int32)
    
    var show = true
    let windowFlags = ImGuiWindowFlags_None.int32 # or ImGuiWindowFlags_NoMove.int32
    if igBeginPopupModal("Generate Payload", addr show, windowFlags):
        defer: igEndPopup()
        
        var availableSize: ImVec2
        igGetContentRegionAvail(addr availableSize)

        # Listener selection
        igText("Listener:       ")
        igSameLine(0.0f, textSpacing)
        igGetContentRegionAvail(addr availableSize)
        igSetNextItemWidth(availableSize.x)
        igCombo_Str("##InputListener", addr component.listener, (listeners.mapIt(it.listenerId).join("\0") & "\0").cstring , listeners.len().int32)

        # Sleep delay
        let step: uint32 = 1
        igText("Sleep delay:    ")
        igSameLine(0.0f, textSpacing)
        igSetNextItemWidth(availableSize.x)
        igInputScalar("##InputSleepDelay", ImGuiDataType_U32.int32, addr component.sleepDelay, addr step, nil, "%hu", ImGui_InputTextFlags_CharsDecimal.int32)

        # Agent sleep obfuscation technique dropdown selection
        igText("Sleep mask:     ")
        igSameLine(0.0f, textSpacing)
        igSetNextItemWidth(availableSize.x)
        igCombo_Str("##InputSleepMask", addr component.sleepMask, (component.sleepMaskTechniques.join("\0") & "\0").cstring , component.sleepMaskTechniques.len().int32)

        # Stack spoofing checkbox (only for EKKO/ZILEAN)
        igText("Stack spoofing: ")
        igSameLine(0.0f, textSpacing)
        igSetNextItemWidth(availableSize.x)

        igBeginDisabled((component.sleepMaskTechniques[component.sleepMask] != $EKKO and component.sleepMaskTechniques[component.sleepMask] != $ZILEAN))
        if (component.sleepMaskTechniques[component.sleepMask] != $EKKO and component.sleepMaskTechniques[component.sleepMask] != $ZILEAN):
            component.spoofStack = false
        igCheckbox("##InputSpoofStack", addr component.spoofStack)
        igEndDisabled()

        igDummy(vec2(0.0f, 10.0f))
        igSeparator()
        igDummy(vec2(0.0f, 10.0f))

        igText("Modules: ")
        
        component.moduleSelection.draw()

        igGetContentRegionAvail(addr availableSize)

        igDummy(vec2(0.0f, 10.0f))
        igSeparator()
        igDummy(vec2(0.0f, 10.0f))

        igText("Build log: ")
        try: 
            # Set styles of the log window
            igPushStyleColor_Vec4(ImGui_Col_FrameBg.int32, vec4(0.1f, 0.1f, 0.1f, 1.0f))
            igPushStyleColor_Vec4(ImGui_Col_ScrollbarBg.int32, vec4(0.1f, 0.1f, 0.1f, 1.0f))
            igPushStyleColor_Vec4(ImGui_Col_Border.int32, vec4(0.2f, 0.2f, 0.2f, 1.0f))
            igPushStyleVar_Float(ImGui_StyleVar_FrameBorderSize .int32, 1.0f)

            let buildLogHeight = 250.0f 
            let childWindowFlags = ImGuiChildFlags_NavFlattened.int32 or ImGui_ChildFlags_Borders.int32 or ImGui_ChildFlags_AlwaysUseWindowPadding.int32 or ImGuiChildFlags_FrameStyle.int32
            if igBeginChild_Str("##Log", vec2(-1.0f, buildLogHeight), childWindowFlags, ImGuiWindowFlags_HorizontalScrollbar.int32):            
                # Display eventlog items
                for item in component.buildLog.items:
                    component.print(item)
                    
                # Auto-scroll to bottom
                if igGetScrollY() >= igGetScrollMaxY():
                    igSetScrollHereY(1.0f)
                        
        except IndexDefect:
            # CTRL+A crashes when no items are in the eventlog
            discard
        
        finally: 
            igPopStyleColor(3)
            igPopStyleVar(1)
            igEndChild()

        igDummy(vec2(0.0f, 10.0f))
        igSeparator()
        igDummy(vec2(0.0f, 10.0f))

        # Enable "Build" button if at least one module has been selected
        igBeginDisabled(component.moduleSelection.items[1].len() == 0)

        if igButton("Build", vec2(availableSize.x * 0.5 - textSpacing * 0.5, 0.0f)):

            # Iterate over modules
            var modules: uint32 = 0
            for m in component.moduleSelection.items[1]: 
                modules = modules or uint32(m.moduleType)

            result = AgentBuildInformation(
                listenerId: listeners[component.listener].listenerId,
                sleepDelay: component.sleepDelay,
                sleepTechnique: cast[SleepObfuscationTechnique](component.sleepMask),
                spoofStack: component.spoofStack,
                modules: modules
            )
        
        igEndDisabled()
        igSameLine(0.0f, textSpacing)

        if igButton("Close", vec2(availableSize.x * 0.5 - textSpacing * 0.5, 0.0f)):
            component.resetModalValues()
            igCloseCurrentPopup()