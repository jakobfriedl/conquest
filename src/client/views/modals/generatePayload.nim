import strutils, strformat, sequtils, tables, times, algorithm
import imguin/[cimgui, glfw_opengl]
import ../widgets/[dualListSelection, textarea]
import ./[configureKillDate, configureWorkingHours]
import ../../utils/[appImGui, globals, utils]
import ../../../types/[common, client]
export addItem

proc PayloadModal*(): PayloadModalComponent =
    result = new PayloadModalComponent
    result.sleepDelay = 5
    result.jitter = 15
    result.workingHours = WorkingHours(
        enabled: false, 
        startHour: 0,
        startMinute: 0,
        endHour: 0,
        endMinute: 0
    )

    # Populate dropdowns
    for agentType in AgentType.low .. AgentType.high: 
        result.agentTypes.add($agentType)
    for payloadType in PayloadType.low .. PayloadType.high:
        result.payloadTypes.add($payloadType)
    for arch in Architecture.low .. Architecture.high:
        result.architectures.add($arch)
    for technique in SleepObfuscationTechnique.low .. SleepObfuscationTechnique.high:
        result.sleepMaskTechniques.add($technique)

    proc compareModules(x, y: Module): int = 
        return cmp(x.name, y.name) 
    proc moduleName(module: Module): string = 
        return module.name
    proc moduleDesc(module: Module): string = 
        result = module.description & "\nModule commands:\n"
        for cmd in module.commands: 
            result &= " - " & cmd.name & "\n"

    result.moduleSelection = DualListSelection(cq.scriptManager.modules.values.toSeq().sorted(compareModules), moduleName, compareModules, moduleDesc)
    result.buildLog = Textarea(showTimestamps = false)
    result.killDateModal = KillDateModal()
    result.workingHoursModal = WorkingHoursModal()

proc resetModalValues*(component: PayloadModalComponent) = 
    component.listener = 0
    component.agentType = 0
    component.arch = 0
    component.payloadType = 0 
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
    component.resetTab = true

proc draw*(component: PayloadModalComponent, listeners: seq[UIListener]): AgentBuildInformation =

    let textSpacing = igGetStyle().ItemSpacing.x
    let markerWidth = igCalcTextSize("(?)", nil, false, -1.0f).x + textSpacing
    
    # Center modal
    let vp = igGetMainViewport()
    var center = ImGuiViewport_GetCenter(vp)
    igSetNextWindowPos(center, ImGuiCond_Appearing.int32, vec2(0.5f, 0.5f))

    let modalWidth = max(500.0f, vp.Size.x * 0.25)
    let modalHeight= max(350.0f, vp.Size.y * 0.25)
    igSetNextWindowSize(vec2(modalWidth, modalHeight), ImGuiCond_Always.int32)
    
    var show = component.show
    let windowFlags = ImGuiWindowFlags_NoResize.int32
    if igBeginPopupModal("Generate Payload", addr show, windowFlags):
        defer: igEndPopup()
        
        component.show = show

        var availableSize = igGetContentRegionAvail()
        if igBeginTabBar("##Tabs", ImGuiTabBarFlags_None.int32): 
            defer: igEndTabBar()

            # Tab 1: General settings
            if igBeginTabItem("General", nil, if component.resetTab: ImGuiTabItemFlags_SetSelected.int32 else: ImGuiTabBarFlags_None.int32):
                defer: igEndTabItem()
                
                if component.resetTab: component.resetTab = false

                igDummy(vec2(0.0f, 8.0f))

                # Agent type selection
                igText("Agent:        ")
                igSameLine(0.0f, textSpacing)
                availableSize = igGetContentRegionAvail()
                igSetNextItemWidth(availableSize.x)
                igCombo_Str("##InputAgentType", addr component.agentType, (component.agentTypes.join("\0") & "\0").cstring, component.agentTypes.len().int32)

                # Architecture selection
                igText("Arch:         ")
                igSameLine(0.0f, textSpacing)
                availableSize = igGetContentRegionAvail()
                igSetNextItemWidth(availableSize.x)
                igCombo_Str("##InputArch", addr component.arch, (component.architectures.join("\0") & "\0").cstring, component.architectures.len().int32)

                # Payload type selection
                igText("Payload type: ")
                igSameLine(0.0f, textSpacing)
                availableSize = igGetContentRegionAvail()
                igSetNextItemWidth(availableSize.x)
                igCombo_Str("##InputPayloadType", addr component.payloadType, (component.payloadTypes.join("\0") & "\0").cstring, component.payloadTypes.len().int32)

                igDummy(vec2(0.0f, 10.0f))
                igSeparator()
                igDummy(vec2(0.0f, 10.0f))

                # Listener selection
                igText("Listener:     ")
                igSameLine(0.0f, textSpacing)
                availableSize = igGetContentRegionAvail()
                igSetNextItemWidth(availableSize.x)
                igCombo_Str("##InputListener", addr component.listener, (listeners.mapIt(it.listenerId & " (" & $it.listenerType & ")").join("\0") & "\0").cstring , listeners.len().int32)

                # Verbose mode checkbox
                igText("Verbose:      ")
                igSameLine(0.0f, textSpacing)
                igCheckbox("##InputVerbose", addr component.verbose)
                igHelpMarker("Verbose mode will cause the agent to print check-ins, tasks and task output on the target system.")

                igDummy(vec2(0.0f, 10.0f))
                igSeparator()
                igDummy(vec2(0.0f, 10.0f))

                # TODO: Execution Guardrails
                # - Domain-joined (optionally specify domain name)
                # - IP-based (IP range, CIDR, comma-separated)
                # - Hostname-based (List of hostnames) 
                # igText("Guardrails:     ")

            # Tab 2: Sleep Settings
            if igBeginTabItem("Sleep", nil, ImGuiTabBarFlags_None.int32):
                defer: igEndTabItem()

                igDummy(vec2(0.0f, 8.0f))

                # Sleep delay
                let step: uint32 = 1
                igText("Sleep delay:    ")
                igSameLine(0.0f, textSpacing)
                availableSize = igGetContentRegionAvail()
                igSetNextItemWidth(availableSize.x - markerWidth)
                igInputScalar("##InputSleepDelay", ImGuiDataType_U32.int32, addr component.sleepDelay, addr step, nil, "%hu", ImGui_InputTextFlags_CharsDecimal.int32)
                igHelpMarker("Sleep delay between heartbeat requests in seconds.")

                # Jitter
                igText("Jitter:         ")
                igSameLine(0.0f, textSpacing)
                igSetNextItemWidth(availableSize.x - markerWidth)
                igSliderInt("##InputJitter", addr component.jitter, 0, 100, "%d%%", ImGui_SliderFlags_None.int32)
                igHelpMarker("Jitter in % to add variation to sleep intervals. Example: A jitter of 20% on a delay of 10 seconds causes the sleep intervals to be anything between 8 and 12 seconds.")

                # Agent sleep obfuscation technique dropdown selection
                igText("Sleepmask:      ")
                igSameLine(0.0f, textSpacing)
                igSetNextItemWidth(availableSize.x - markerWidth)
                igCombo_Str("##InputSleepMask", addr component.sleepMask, (component.sleepMaskTechniques.join("\0") & "\0").cstring , component.sleepMaskTechniques.len().int32)
                igHelpMarker("""Conquest supports the following sleep obfuscation techniques:
- NONE    : Regular delayed execution using WaitForSingleObject
- EKKO    : Obfuscate agent memory during sleep using Timers API (RtlCreateTimer)
- ZILEAN  : Obfuscate agent memory during sleep using Timers API (RtlRegisterWait)
- FOLIAGE : Obfuscate agent memory during sleep using Asynchronous Procedure Calls (APC)""")

                # Stack spoofing checkbox (only for EKKO/ZILEAN)
                igText("Stack spoofing: ")
                igSameLine(0.0f, textSpacing)
                igSetNextItemWidth(availableSize.x)

                igBeginDisabled((component.sleepMaskTechniques[component.sleepMask] != $EKKO and component.sleepMaskTechniques[component.sleepMask] != $ZILEAN))
                if (component.sleepMaskTechniques[component.sleepMask] != $EKKO and component.sleepMaskTechniques[component.sleepMask] != $ZILEAN):
                    component.spoofStack = false
                igCheckbox("##InputSpoofStack", addr component.spoofStack)
                igEndDisabled()
                igHelpMarker("Spoof the call stack while sleeping by duplicating another thread's stack.\n\nOnly available when EKKO or ZILEAN are used for sleep obfuscation.")
                igDummy(vec2(0.0f, 10.0f))
                igSeparator()
                igDummy(vec2(0.0f, 10.0f))

                # Kill date (checkbox & button to choose date)
                igText("Kill date:      ")
                igSameLine(0.0f, textSpacing)
                igCheckbox("##InputKillDate", addr component.killDateEnabled)        
                igSameLine(0.0f, textSpacing)
                
                igBeginDisabled(not component.killDateEnabled)
                availableSize = igGetContentRegionAvail()
                if igButton((if component.killDate != 0: component.killDate.fromUnix().utc().format("dd. MMMM yyyy HH:mm:ss") & " UTC" else: "Configure##KillDate").cstring, vec2(availableSize.x - markerWidth, 0.0f)):
                    igOpenPopup_str("Configure Kill Date", ImGui_PopupFlags_None.int32)
                igEndDisabled()
                igHelpMarker("The agent terminates after the configured date & time (UTC) has been reached.")

                let killDate = component.killDateModal.draw()
                if killDate != 0:
                    component.killDate = killDate

                # Working hours
                igText("Working hours:  ")
                igSameLine(0.0f, textSpacing)
                igCheckbox("##InputWorkingHours", addr component.workingHoursEnabled)
                igSameLine(0.0f, textSpacing)

                igBeginDisabled(not component.workingHoursEnabled)
                availableSize = igGetContentRegionAvail()
                let workingHoursLabel = fmt"{component.workingHours.startHour:02}:{component.workingHours.startMinute:02} - {component.workingHours.endHour:02}:{component.workingHours.endMinute:02}"
                if igButton((if component.workingHours.enabled: workingHoursLabel else: "Configure##WorkingHours").cstring, vec2(availableSize.x - markerWidth, 0.0f)):
                    igOpenPopup_str("Configure Working Hours", ImGui_PopupFlags_None.int32)
                igEndDisabled()
                igHelpMarker("The agent only calls back in the regular sleep interval during the configured working hours.")

                let workingHours = component.workingHoursModal.draw()
                if workingHours.enabled: 
                    component.workingHours = workingHours

            # TODO: OPSEC/Evasion Settings
            # if igBeginTabItem("Evasion", nil, ImGuiTabBarFlags_None.int32):
            #     defer: igEndTabItem()

            #     igText("TODO")

            # Tab 3: Modules
            if igBeginTabItem("Modules", nil, ImGuiTabBarFlags_None.int32):
                defer: igEndTabItem()

                igDummy(vec2(0.0f, 8.0f))
                component.moduleSelection.draw()

            # TODO: Config Preview
            # if igBeginTabItem("Preview", nil, ImGuiTabBarFlags_None.int32):
            #     defer: igEndTabItem()

            #     igText("TODO")

            # Tab 4: Build Log
            if igBeginTabItem("Build", nil, ImGuiTabBarFlags_None.int32):
                defer: igEndTabItem()

                igDummy(vec2(0.0f, 8.0f))

                let style = igGetStyle()
                let reserve = 10.0f + 1.0f + 10.0f + igGetFrameHeight() + style.ItemSpacing.y * 5.0f
                let logHeight = igGetContentRegionAvail().y - reserve
                component.buildLog.draw(vec2(-1.0f, logHeight))

                igDummy(vec2(0.0f, 10.0f))
                igSeparator()
                igDummy(vec2(0.0f, 10.0f))

                # Enable "Build" button if at least one module has been selected
                igBeginDisabled(component.moduleSelection.items[1].len() == 0)

                availableSize = igGetContentRegionAvail()
                if igButton("Build", vec2(availableSize.x * 0.5 - textSpacing * 0.5, 0.0f)):

                    component.buildLog.clear()

                    # Iterate over modules
                    var modules: uint32 = 0

                    for m in component.moduleSelection.items[1]: 
                        modules = modules or uint32(parseModuleType(m.name))

                    result = AgentBuildInformation(
                        listenerId: listeners[component.listener].listenerId,
                        agentType: cast[AgentType](component.agentType),
                        arch: cast[Architecture](component.arch),
                        payloadType: cast[PayloadType](component.payloadType),  # Cast int32 to PayloadType
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