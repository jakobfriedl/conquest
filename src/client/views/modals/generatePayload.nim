import strutils, strformat, sequtils, times
import imguin/[cimgui, glfw_opengl, simple]
import ../../utils/[appImGui, colors]
import ../../../common/[types, profile, utils]
import ../../../modules/manager
import ../widgets/[dualListSelection, textarea]
import ./[configureKillDate, configureWorkingHours]
export addItem

type 
    AgentModalComponent* = ref object of RootObj
        listener: int32 
        sleepDelay: uint32
        jitter: int32 
        sleepMask: int32 
        spoofStack: bool 
        killDateEnabled: bool 
        killDate: int64
        workingHoursEnabled: bool
        workingHours: WorkingHours
        verbose: bool
        sleepMaskTechniques: seq[string]
        moduleSelection: DualListSelectionWidget[Module]
        buildLog*: TextareaWidget
        killDateModal*: KillDateModalComponent
        workingHoursModal*: WorkingHoursModalComponent


proc AgentModal*(): AgentModalComponent =
    result = new AgentModalComponent
    result.listener = 0
    result.sleepDelay = 5
    result.jitter = 15
    result.sleepMask = 0
    result.spoofStack = false
    result.killDateEnabled = false
    result.killDate = 0
    result.workingHoursEnabled = false 
    result.workingHours = WorkingHours(
        enabled: false, 
        startHour: 0,
        startMinute: 0,
        endHour: 0,
        endMinute: 0
    )
    result.verbose = false

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
    result.killDateModal = KillDateModal()
    result.workingHoursModal = WorkingHoursModal()

proc resetModalValues*(component: AgentModalComponent) = 
    component.listener = 0
    component.sleepDelay = 5
    component.jitter = 15
    component.sleepMask = 0
    component.spoofStack = false 
    component.killDateEnabled = false
    component.killDate = 0
    component.workingHoursEnabled = false
    component.workingHours = WorkingHours(
        enabled: false, 
        startHour: 0,
        startMinute: 0,
        endHour: 0,
        endMinute: 0
    )
    component.verbose = false
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

        # Jitter
        igText("Jitter:         ")
        igSameLine(0.0f, textSpacing)
        igSetNextItemWidth(availableSize.x)
        igSliderInt("##InputJitter", addr component.jitter, 0, 100, "%d%%", ImGui_SliderFlags_None.int32)

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

        # Verbose mode checkbox
        igText("Verbose:        ")
        igSameLine(0.0f, textSpacing)
        igSetNextItemWidth(availableSize.x)
        igCheckbox("##InputVerbose", addr component.verbose)

        igDummy(vec2(0.0f, 10.0f))
        igSeparator()
        igDummy(vec2(0.0f, 10.0f))

        # Kill date (checkbox & button to choose date)
        igText("Kill date:      ")
        igSameLine(0.0f, textSpacing)
        igCheckbox("##InputKillDate", addr component.killDateEnabled)        
        igSameLine(0.0f, textSpacing)
        
        igBeginDisabled(not component.killDateEnabled)
        igGetContentRegionAvail(addr availableSize)
        igSetNextItemWidth(availableSize.x)
        if igButton(if component.killDate != 0: component.killDate.fromUnix().utc().format("dd. MMMM yyyy HH:mm:ss")  & " UTC" else: "Configure##KillDate", vec2(-1.0f, 0.0f)):
            igOpenPopup_str("Configure Kill Date", ImGui_PopupFlags_None.int32) 
        igEndDisabled()

        let killDate = component.killDateModal.draw()
        if killDate != 0: 
            component.killDate = killDate

        # Working hours
        igText("Working hours:  ")
        igSameLine(0.0f, textSpacing)
        igCheckbox("##InputWorkingHours", addr component.workingHoursEnabled)        
        igSameLine(0.0f, textSpacing)
        
        igBeginDisabled(not component.workingHoursEnabled)
        igGetContentRegionAvail(addr availableSize)
        igSetNextItemWidth(availableSize.x)

        let workingHoursLabel = fmt"{component.workingHours.startHour:02}:{component.workingHours.startMinute:02} - {component.workingHours.endHour:02}:{component.workingHours.endMinute:02}"
        if igButton(if component.workingHours.enabled: workingHoursLabel else: "Configure##WorkingHours", vec2(-1.0f, 0.0f)):
            igOpenPopup_str("Configure Working Hours", ImGui_PopupFlags_None.int32) 
        igEndDisabled()

        let workingHours = component.workingHoursModal.draw()
        if workingHours.enabled: 
            component.workingHours = workingHours

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
        let buildLogHeight = igGetTextLineHeightWithSpacing() * 7.0f  + igGetStyle().ItemSpacing.y
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
                sleepSettings: SleepSettings(
                    sleepDelay: component.sleepDelay,
                    jitter: cast[uint32](component.jitter), 
                    sleepTechnique: cast[SleepObfuscationTechnique](component.sleepMask),
                    spoofStack: component.spoofStack,
                    workingHours: if component.workingHoursEnabled: component.workingHours else: WorkingHours(enabled: false, startHour: 0, startMinute: 0, endHour: 0, endMinute: 0)
                ),
                verbose: component.verbose,
                killDate: if component.killDateEnabled: component.killDate else: 0, 
                modules: modules
            )
        
        igEndDisabled()
        igSameLine(0.0f, textSpacing)

        if igButton("Close", vec2(availableSize.x * 0.5 - textSpacing * 0.5, 0.0f)):
            component.resetModalValues()
            igCloseCurrentPopup()