import strutils, sequtils, times
import imguin/[cimgui, glfw_opengl, simple]
import ../../utils/[appImGui, colors]
import ../../../common/[types, profile, utils]
import ../../../modules/manager
import ../widgets/[dualListSelection, textarea]
export addItem

type 
    AgentModalComponent* = ref object of RootObj
        listener: int32 
        sleepDelay: uint32 
        sleepMask: int32 
        spoofStack: bool 
        sleepMaskTechniques: seq[string]
        moduleSelection: DualListSelectionWidget[Module]
        buildLog*: TextareaWidget


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
    result.buildLog = Textarea(showTimestamps = false)

proc resetModalValues*(component: AgentModalComponent) = 
    component.listener = 0
    component.sleepDelay = 5
    component.sleepMask = 0
    component.spoofStack = false 
    component.moduleSelection.reset()
    component.buildLog.clear()

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
        let buildLogHeight = 250.0f 
        component.buildLog.draw(vec2(-1.0f, buildLogHeight))

        igDummy(vec2(0.0f, 10.0f))
        igSeparator()
        igDummy(vec2(0.0f, 10.0f))

        # Enable "Build" button if at least one module has been selected
        igBeginDisabled(component.moduleSelection.items[1].len() == 0)

        if igButton("Build", vec2(availableSize.x * 0.5 - textSpacing * 0.5, 0.0f)):

            component.buildLog.clear()

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