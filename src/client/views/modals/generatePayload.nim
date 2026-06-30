import strutils, strformat, sequtils, tables, times, algorithm, regex, json, std/enumutils
import imguin/[cimgui, glfw_opengl]
import ../widgets/[dualListSelection, textarea]
import ./[configureKillDate, configureWorkingHours]
import ../../utils/[appImGui, globals, utils, dialogs]
import ../../../types/[common, client]
export addItem

proc compareModules(x, y: Module): int = 
    return cmp(x.name, y.name) 
proc moduleName(module: Module): string = 
    return module.name
proc moduleDesc(module: Module): string = 
    result = module.description & "\nModule commands:\n"
    for cmd in module.commands: 
        result &= " - " & cmd.name & "\n"

proc PayloadModal*(): PayloadModalComponent =
    result = new PayloadModalComponent
    
    # Default values 
    result.sleepDelay = 5
    result.jitter = 15

    zeroMem(addr result.domainGuardrail[0], MAX_INPUT_LENGTH)
    zeroMem(addr result.ipGuardrail[0], MAX_INPUT_LENGTH)
    zeroMem(addr result.hostGuardrail[0], MAX_INPUT_LENGTH)
    result.workingHours = WorkingHours(
        enabled: false, 
        startHour: 0,
        startMinute: 0,
        endHour: 0,
        endMinute: 0
    )

    # Populate dropdowns
    for agentType in AgentType: 
        result.agentTypes &= $agentType & "\0"
    for payloadType in PayloadType:
        result.payloadTypes &= $payloadType & "\0"
    for arch in Architecture:
        result.architectures &= $arch & "\0"
    for technique in SleepObfuscationTechnique:
        result.sleepMaskTechniques &= $technique & "\0"

    result.moduleSelection = DualListSelection(cq.scriptManager.modules.values.toSeq().sorted(compareModules), moduleName, compareModules, moduleDesc)
    
    result.configPreview = Textarea(showTimestamps = false, autoScroll = false)
    result.buildLog = Textarea(showTimestamps = false)
    
    result.killDateModal = KillDateModal()
    result.workingHoursModal = WorkingHoursModal()

proc resetModalValues*(component: PayloadModalComponent) = 
    # General
    component.listener = 0
    component.agentType = 0
    component.arch = 0
    component.payloadType = 0 
    component.verbose = false
    
    # Sleep settings
    component.sleepDelay = 5
    component.jitter = 15
    component.sleepMask = 0
    component.spoofStack = false 

    # Guardrails
    component.domainGuardrailEnabled = false
    zeroMem(addr component.domainGuardrail[0], MAX_INPUT_LENGTH)
    component.ipGuardrailEnabled = false
    zeroMem(addr component.ipGuardrail[0], MAX_INPUT_LENGTH)
    component.hostGuardrailEnabled = false
    zeroMem(addr component.hostGuardrail[0], MAX_INPUT_LENGTH)

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

    component.selfDelete = false

    component.moduleSelection.reset()
    component.buildLog.clear()
    component.resetTab = true

#[
    Validation
]#
proc igBeginTabItemWithValidation*(label: string, hasError: bool): bool =
    if hasError:
        igPushStyleColor(ImGuiCol_Tab.int32, CONSOLE_ERROR_DIM)
        igPushStyleColor(ImGuiCol_TabHovered.int32, CONSOLE_ERROR_HOVERED)
        igPushStyleColor(ImGuiCol_TabSelected.int32, CONSOLE_ERROR)
    result = igBeginTabItem(label.cstring, nil, ImGuiTabBarFlags_None.int32)
    if hasError: 
        igPopStyleColor(3)

proc validateDomainGuardrail(input: string): string =
    if input.strip().len() == 0: return ""
    let pattern = re2"[a-zA-Z0-9][a-zA-Z0-9\-\*\?\.]*"
    for raw in input.split(','):
        let entry = raw.strip()
        if entry.len() == 0: return "Empty entry in list."
        let value = if entry.startsWith("!"): entry[1..^1] else: entry
        if not value.match(pattern): return "Invalid entry: '" & entry & "'"
    return ""

proc validateIPGuardrail(input: string): string =
    if input.strip().len() == 0: return "At least one IP entry required."
    let pattern = re2"(\d{1,3}|\*)\.(\d{1,3}|\*)\.(\d{1,3}|\*)\.(\d{1,3}|\*)"
    for raw in input.split(','):
        let entry = raw.strip()
        if entry.len() == 0: return "Empty entry in list."
        let value = if entry.startsWith("!"): entry[1..^1] else: entry
        if not value.match(pattern): return "Invalid IP: '" & entry & "'"
        for part in value.split('.'):
            if part != "*":
                try:
                    if part.parseInt > 255: return "Octet out of range in '" & entry & "'"
                except: return "Invalid octet in '" & entry & "'"
    return ""

proc validateHostnameGuardrail(input: string): string =
    if input.strip().len() == 0: return "At least one hostname entry required."
    let pattern = re2"[a-zA-Z0-9\*\?][a-zA-Z0-9\-\*\?]*"
    for raw in input.split(','):
        let entry = raw.strip()
        if entry.len() == 0: return "Empty entry in list."
        let value = if entry.startsWith("!"): entry[1..^1] else: entry
        if not value.match(pattern): return "Invalid hostname: '" & entry & "'"
    return ""

proc validateKillDate(input: int): string =
    if input == 0: 
        return "Missing kill date configuration."
    if input <= now().toTime().toUnix(): 
        return "Kill date must not be in the past."
    return ""

#[
    Save/load payload configuration from JSON file
]#
proc serializeConfig(component: PayloadModalComponent): string =
    var config = newJObject()

    config["agentType"] = %symbolName(AgentType(component.agentType))
    config["arch"] = %symbolName(Architecture(component.arch))
    config["payloadType"] = %symbolName(PayloadType(component.payloadType))
    config["verbose"] = %component.verbose
    config["sleepDelay"] = %component.sleepDelay.int
    config["jitter"] = %component.jitter.int
    config["sleepMask"] = %symbolName(SleepObfuscationTechnique(component.sleepMask))
    config["spoofStack"] = %component.spoofStack

    config["workingHours"] = newJObject()
    if component.workingHoursEnabled and component.workingHours.enabled:
        config["workingHours"]["startHour"] = %component.workingHours.startHour.int
        config["workingHours"]["startMinute"] = %component.workingHours.startMinute.int
        config["workingHours"]["endHour"] = %component.workingHours.endHour.int
        config["workingHours"]["endMinute"] = %component.workingHours.endMinute.int

    config["guardrails"] = newJObject()
    if component.domainGuardrailEnabled: config["guardrails"]["domain"] = %(component.domainGuardrail.toString())
    if component.ipGuardrailEnabled: config["guardrails"]["ip"] = %(component.ipGuardrail.toString())
    if component.hostGuardrailEnabled: config["guardrails"]["hostname"] = %(component.hostGuardrail.toString())
    config["killDate"] = %(if component.killDateEnabled: component.killDate else: 0'i64)
    config["selfDelete"] = %component.selfDelete

    config["modules"] = %component.moduleSelection.items[1].mapIt(it.name)
    return config.pretty()

proc saveBuildConfig(component: PayloadModalComponent, configPath: string) =
    if configPath.len == 0: 
        return
    writeFile(configPath, component.serializeConfig())

proc parseEnumBySymbol[T: enum](s: string): T =
    for e in low(T)..high(T):
        if symbolName(e) == s:
            return e
    raise newException(ValueError, "Invalid enum symbol: " & s)

proc loadBuildConfig(component: PayloadModalComponent, configPath: string) =
    if configPath.len == 0: 
        return
    let configJson = parseJson(readFile(configPath))

    component.agentType = int32(parseEnumBySymbol[AgentType](configJson["agentType"].getStr()))
    component.arch = int32(parseEnumBySymbol[Architecture](configJson["arch"].getStr()))
    component.payloadType = int32(parseEnumBySymbol[PayloadType](configJson["payloadType"].getStr()))
    component.verbose = configJson["verbose"].getBool()
    component.sleepDelay = configJson["sleepDelay"].getInt().uint32
    component.jitter = configJson["jitter"].getInt().int32
    component.sleepMask = int32(parseEnumBySymbol[SleepObfuscationTechnique](configJson["sleepMask"].getStr()))
    component.spoofStack = configJson["spoofStack"].getBool()

    # Guardrails
    proc loadGuardrail(key: string, enabled: var bool, buf: var array[MAX_INPUT_LENGTH, char], val: JsonNode) =
        enabled = val.hasKey(key)
        zeroMem(addr buf[0], MAX_INPUT_LENGTH)
        if enabled:
            let s = val[key].getStr()
            copyMem(addr buf[0], cstring(s), min(s.len, MAX_INPUT_LENGTH - 1))

    loadGuardrail("domain", component.domainGuardrailEnabled, component.domainGuardrail, configJson["guardrails"])
    loadGuardrail("ip", component.ipGuardrailEnabled, component.ipGuardrail, configJson["guardrails"])
    loadGuardrail("hostname", component.hostGuardrailEnabled, component.hostGuardrail, configJson["guardrails"])

    component.killDate = configJson["killDate"].getBiggestInt()
    component.killDateEnabled = component.killDate != 0
    component.workingHours = WorkingHours(
        enabled: configJson["workingHours"].len() > 0,
        startHour: configJson["workingHours"].getOrDefault("startHour").getInt().int32,
        startMinute: configJson["workingHours"].getOrDefault("startMinute").getInt().int32,
        endHour: configJson["workingHours"].getOrDefault("endHour").getInt().int32,
        endMinute: configJson["workingHours"].getOrDefault("endMinute").getInt().int32
    )
    component.selfDelete = configJson["selfDelete"].getBool() 
    component.workingHoursEnabled = component.workingHours.enabled

    # Modules
    component.moduleSelection.reset()
    let selectedNames = configJson["modules"].getElems().mapIt(it.getStr())
    let modules = cq.scriptManager.modules.values.toSeq()
    component.moduleSelection.items[0] = modules.filterIt(it.name notin selectedNames)
    component.moduleSelection.items[1] = modules.filterIt(it.name in selectedNames).sorted(compareModules)

proc draw*(component: PayloadModalComponent, listeners: seq[UIListener]): AgentBuildInformation =

    let textSpacing = igGetStyle().ItemSpacing.x
    let markerWidth = igCalcTextSize("(?)", nil, false, -1.0f).x + textSpacing
    
    # Center modal
    let vp = igGetMainViewport()
    var center = ImGuiViewport_GetCenter(vp)
    igSetNextWindowPos(center, ImGuiCond_Appearing.int32, vec2(0.5f, 0.5f))

    let modalWidth = max(500.0f, vp.Size.x * 0.25)
    let modalHeight= max(360.0f, vp.Size.y * 0.25)
    igSetNextWindowSize(vec2(modalWidth, modalHeight), ImGuiCond_Always.int32)
    
    var show = component.show
    let windowFlags = ImGuiWindowFlags_NoResize.int32
    if igBeginPopupModal("Generate Payload", addr show, windowFlags):
        defer: igEndPopup()
        
        component.show = show

        var availableSize = igGetContentRegionAvail()

        # Input/settings validation 
        let domainError = if component.domainGuardrailEnabled: validateDomainGuardrail(component.domainGuardrail.toString()) else: ""
        let ipError = if component.ipGuardrailEnabled: validateIPGuardrail(component.ipGuardrail.toString()) else: ""
        let hostError = if component.hostGuardrailEnabled: validateHostnameGuardrail(component.hostGuardrail.toString()) else: ""
        let killDateError = if component.killDateEnabled: validateKillDate(component.killDate) else: ""
        let workingHoursError = if component.workingHoursEnabled and not component.workingHours.enabled: "Missing working hours configuration." else: ""
        
        let sleepError = workingHoursError.len() > 0
        let guardrailsError = domainError.len() > 0 or ipError.len() > 0 or hostError.len() > 0 or killDateError.len() > 0
        let modulesError = component.moduleSelection.items[1].len() == 0

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
                igCombo_Str("##InputAgentType", addr component.agentType, component.agentTypes.cstring, component.agentTypes.len().int32)

                # Architecture selection
                igText("Arch:         ")
                igSameLine(0.0f, textSpacing)
                availableSize = igGetContentRegionAvail()
                igSetNextItemWidth(availableSize.x)
                igCombo_Str("##InputArch", addr component.arch, component.architectures.cstring, component.architectures.len().int32)

                # Payload type selection
                igText("Payload type: ")
                igSameLine(0.0f, textSpacing)
                availableSize = igGetContentRegionAvail()
                igSetNextItemWidth(availableSize.x)
                igCombo_Str("##InputPayloadType", addr component.payloadType, component.payloadTypes.cstring, component.payloadTypes.len().int32)

                igDummy(vec2(0.0f, 10.0f))
                igSeparator()
                igDummy(vec2(0.0f, 10.0f))

                # Listener selection
                igText("Listener:     ")
                igSameLine(0.0f, textSpacing)
                availableSize = igGetContentRegionAvail()
                igSetNextItemWidth(availableSize.x)
                igCombo_Str("##InputListener", addr component.listener, (listeners.mapIt(it.name & " (" & $it.listenerType & ")").join("\0") & "\0").cstring , listeners.len().int32)

                # Verbose mode checkbox
                igText("Verbose:      ")
                igSameLine(0.0f, textSpacing)
                igCheckbox("##InputVerbose", addr component.verbose)
                igHelpMarker("Verbose mode will cause the agent to print check-ins, tasks and task output on the target system.")

            # Tab 2: Sleep Settings
            if igBeginTabItemWithValidation("Sleep", sleepError):
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
                igCombo_Str("##InputSleepMask", addr component.sleepMask, component.sleepMaskTechniques.cstring , component.sleepMaskTechniques.len().int32)
                igHelpMarker("""Conquest supports the following sleep obfuscation techniques:
- NONE: Regular delayed execution using WaitForSingleObject.
- EKKO: Encrypt agent memory during sleep via RtlCreateTimer.
- ZILEAN: Encrypt agent memory during sleep via RtlRegisterWait.
- FOLIAGE: Encrypt agent memory during sleep via Asynchronous Procedure Calls.""")

                # Stack spoofing checkbox (only for EKKO/ZILEAN)
                igText("Stack spoofing: ")
                igSameLine(0.0f, textSpacing)
                igSetNextItemWidth(availableSize.x)

                igBeginDisabled((component.sleepMask != EKKO.int32 and component.sleepMask != ZILEAN.int32))
                if (component.sleepMask != EKKO.int32 and component.sleepMask != ZILEAN.int32):
                    component.spoofStack = false
                igCheckbox("##InputSpoofStack", addr component.spoofStack)
                igEndDisabled()
                igHelpMarker("Spoof the call stack while sleeping by duplicating another thread's stack.\n\nOnly available when EKKO or ZILEAN are used for sleep obfuscation.")
                
                igDummy(vec2(0.0f, 10.0f))
                igSeparator()
                igDummy(vec2(0.0f, 10.0f))

                # Working hours
                igText("Working hours: ")
                igSameLine(0.0f, textSpacing)
                igCheckbox("##InputWorkingHours", addr component.workingHoursEnabled)
                igSameLine(0.0f, textSpacing)

                if workingHoursError.len() > 0:
                    igPushStyleColor(ImGuiCol_Button.int32, CONSOLE_ERROR_DIM)
                    igPushStyleColor(ImGuiCol_ButtonHovered.int32, CONSOLE_ERROR_HOVERED)
                    igPushStyleColor(ImGuiCol_ButtonActive.int32, CONSOLE_ERROR)
                
                igBeginDisabled(not component.workingHoursEnabled)
                availableSize = igGetContentRegionAvail()
                let workingHoursLabel = fmt"{component.workingHours.startHour:02}:{component.workingHours.startMinute:02} - {component.workingHours.endHour:02}:{component.workingHours.endMinute:02}"
                if igButton((if component.workingHours.enabled: workingHoursLabel else: "Configure##WorkingHours").cstring, vec2(availableSize.x - markerWidth, 0.0f)):
                    igOpenPopup_str("Configure Working Hours", ImGui_PopupFlags_None.int32)
                igEndDisabled()
                
                if workingHoursError.len() > 0:
                    igPopStyleColor(3)
                    if igIsItemHovered(0): setTooltip(workingHoursError)
                igHelpMarker("The agent only calls back in the regular sleep interval during the configured working hours.")

                let workingHours = component.workingHoursModal.draw()
                if workingHours.enabled: 
                    component.workingHours = workingHours

                igDummy(vec2(0.0f, 10.0f))
                igSeparator()
                igDummy(vec2(0.0f, 10.0f))

                let 
                    delayMin = component.sleepDelay.float * (1.0 - component.jitter.float / 100.0)
                    delayMax = component.sleepDelay.float * (1.0 + component.jitter.float / 100.0)
                igText(fmt"Sleep delay can range from {delayMin:.1f}s to {delayMax:.1f}s.".cstring)
            
            # Tab 3: Guardrails
            if igBeginTabItemWithValidation("Guardrails", guardrailsError):
                defer: igEndTabItem()

                igDummy(vec2(0.0f, 8.0f))

                # Execution guardrails
                igText("Guardrails")
                igSameLine(0.0f, textSpacing)
                igHelpMarker("Execution guardrails terminate the agent if the target does not match all configured conditions. This is useful to prevent the agent from being executed in a sandbox environment or on an out-of-scope target.\n\nGuardrails support wildcards (* and ?) and negation prefixes (!).")

                # Domain Guardrail
                # Execute only on domain-joined machines. Optionally, pass a specific AD domain to check for.
                igText("  Domain:      ")
                igSameLine(0.0f, textSpacing)
                igCheckbox("##InputDomainGuardrail", addr component.domainGuardrailEnabled)
                igSameLine(0.0f, textSpacing)

                if domainError.len() > 0:
                    igPushStyleColor(ImGuiCol_FrameBg.int32, CONSOLE_ERROR_DIM)
                    igPushStyleColor(ImGuiCol_FrameBgHovered.int32, CONSOLE_ERROR_HOVERED)
                    igPushStyleColor(ImGuiCol_FrameBgActive.int32, CONSOLE_ERROR)
                
                igBeginDisabled(not component.domainGuardrailEnabled)
                availableSize = igGetContentRegionAvail()
                igSetNextItemWidth(availableSize.x - markerWidth)
                igInputTextWithHint("##InputDomain", (if component.domainGuardrailEnabled: "Any domain-joined target" else: "conquest.local").cstring, cast[cstring](addr component.domainGuardrail[0]), MAX_INPUT_LENGTH, ImGui_InputTextFlags_None.int32, nil, nil)
                igEndDisabled()
                
                if domainError.len() > 0:
                    igPopStyleColor(3)
                    if igIsItemHovered(0): setTooltip(domainError)
                igHelpMarker("Comma-separated AD domain patterns. Leave empty to match any domain-joined host.")

                # IP Guardrail
                # Execute only on systems with a specific IP address.
                igText("  IP Address:  ")
                igSameLine(0.0f, textSpacing)
                igCheckbox("##InputIPGuardrail", addr component.ipGuardrailEnabled)
                igSameLine(0.0f, textSpacing)

                if ipError.len() > 0:
                    igPushStyleColor(ImGuiCol_FrameBg.int32, CONSOLE_ERROR_DIM)
                    igPushStyleColor(ImGuiCol_FrameBgHovered.int32, CONSOLE_ERROR_HOVERED)
                    igPushStyleColor(ImGuiCol_FrameBgActive.int32, CONSOLE_ERROR)
                
                igBeginDisabled(not component.ipGuardrailEnabled)
                availableSize = igGetContentRegionAvail()
                igSetNextItemWidth(availableSize.x - markerWidth)
                igInputTextWithHint("##InputIP", (if component.ipGuardrailEnabled: "" else: "192.168.168.*,!192.168.168.50").cstring, cast[cstring](addr component.ipGuardrail[0]), MAX_INPUT_LENGTH, ImGui_InputTextFlags_None.int32, nil, nil)
                igEndDisabled()
                
                if ipError.len() > 0:
                    igPopStyleColor(3)
                    if igIsItemHovered(0): setTooltip(ipError)
                igHelpMarker("Comma-separated IP address patterns.")

                # Hostname Guardrail
                # Execute only on systems with a specific hostname.
                igText("  Hostname:    ")
                igSameLine(0.0f, textSpacing)
                igCheckbox("##InputHostGuardrail", addr component.hostGuardrailEnabled)
                igSameLine(0.0f, textSpacing)

                if hostError.len() > 0:
                    igPushStyleColor(ImGuiCol_FrameBg.int32, CONSOLE_ERROR_DIM)
                    igPushStyleColor(ImGuiCol_FrameBgHovered.int32, CONSOLE_ERROR_HOVERED)
                    igPushStyleColor(ImGuiCol_FrameBgActive.int32, CONSOLE_ERROR)
                
                igBeginDisabled(not component.hostGuardrailEnabled)
                availableSize = igGetContentRegionAvail()
                igSetNextItemWidth(availableSize.x - markerWidth)
                igInputTextWithHint("##InputHostname", (if component.hostGuardrailEnabled: "" else: "SRV-*,!*-OT*-").cstring, cast[cstring](addr component.hostGuardrail[0]), MAX_INPUT_LENGTH, ImGui_InputTextFlags_None.int32, nil, nil)
                igEndDisabled()
                
                if hostError.len() > 0:
                    igPopStyleColor(3)
                    if igIsItemHovered(0): setTooltip(hostError)
                igHelpMarker("Comma-separated hostname patterns.")

                igDummy(vec2(0.0f, 10.0f))
                igSeparator()
                igDummy(vec2(0.0f, 10.0f))

                # Kill date (checkbox & button to choose date)
                igText("Kill date:     ")
                igSameLine(0.0f, textSpacing)
                igCheckbox("##InputKillDate", addr component.killDateEnabled)        
                igSameLine(0.0f, textSpacing)
                
                if killDateError.len() > 0:
                    igPushStyleColor(ImGuiCol_Button.int32, CONSOLE_ERROR_DIM)
                    igPushStyleColor(ImGuiCol_ButtonHovered.int32, CONSOLE_ERROR_HOVERED)
                    igPushStyleColor(ImGuiCol_ButtonActive.int32, CONSOLE_ERROR)
                
                igBeginDisabled(not component.killDateEnabled)
                availableSize = igGetContentRegionAvail()
                if igButton((if component.killDate != 0: component.killDate.fromUnix().utc().format("dd. MMMM yyyy HH:mm:ss") & " UTC" else: "Configure##KillDate").cstring, vec2(availableSize.x - markerWidth, 0.0f)):
                    igOpenPopup_str("Configure Kill Date", ImGui_PopupFlags_None.int32)
                igEndDisabled()
                
                if killDateError.len() > 0:
                    igPopStyleColor(3)
                    if igIsItemHovered(0): setTooltip(killDateError)
                igHelpMarker("The agent terminates after the configured date & time (UTC) has been reached.")

                let killDate = component.killDateModal.draw()
                if killDate != 0:
                    component.killDate = killDate
                
                igDummy(vec2(0.0f, 10.0f))
                igSeparator()
                igDummy(vec2(0.0f, 10.0f))

                # Self-delete checkbox
                igText("Self-delete:   ")
                igSameLine(0.0f, textSpacing)

                igBeginDisabled(component.payloadType != PAYLOAD_EXE.int32)
                if component.payloadType != PAYLOAD_EXE.int32: 
                    component.selfDelete = false 
                igCheckbox("##InputselfDelete", addr component.selfDelete)
                igEndDisabled()
                igHelpMarker("Remove the executable from disk when a execution guardrail condition is met and the agent terminates.\n\nThis option is only available for regular Windows executables (.exe).")

            # Tab 4: Modules
            if igBeginTabItemWithValidation("Modules", modulesError):
                defer: igEndTabItem()

                igDummy(vec2(0.0f, 8.0f))
                component.moduleSelection.draw()

            # Tab 5: Config Preview
            if igBeginTabItem("Config", nil, ImGuiTabBarFlags_None.int32):
                defer: igEndTabItem()

                igDummy(vec2(0.0f, 8.0f))

                let style = igGetStyle()
                let reserve = 10.0f + 1.0f + 10.0f + igGetFrameHeight() + style.ItemSpacing.y * 5.0f
                let logHeight = igGetContentRegionAvail().y - reserve
                
                # Only update the config preview if the settings have changed
                let configJson = component.serializeConfig()
                if configJson != component.configJson:
                    component.configJson = configJson
                    component.configPreview.clear()
                    component.configPreview.addItem(LOG_OUTPUT, configJson)
                component.configPreview.draw(vec2(-1.0f, logHeight))

                igDummy(vec2(0.0f, 10.0f))
                igSeparator()
                igDummy(vec2(0.0f, 10.0f))

                availableSize = igGetContentRegionAvail()            
                if igButton("Import", vec2(availableSize.x * 0.5 - textSpacing * 0.5, 0.0f)):
                    let path = callDialogFileOpen("Load Build Config", "", [("*.json", "*.json")])
                    component.loadBuildConfig(path)
                igSameLine(0.0f, textSpacing)

                # Disable export button when there are config errors
                igBeginDisabled(sleepError or guardrailsError or modulesError)
                if igButton("Export", vec2(availableSize.x * 0.5 - textSpacing * 0.5, 0.0f)):
                    let path = callDialogFileSave("Save Build Config", "config.json")
                    component.saveBuildConfig(path) 
                igEndDisabled()

            # Tab 6: Build Log
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

                # Enable "Build" button if there are no missing settings or errors
                igBeginDisabled(sleepError or guardrailsError or modulesError)
                availableSize = igGetContentRegionAvail()
                if igButton("Build", vec2(availableSize.x * 0.5 - textSpacing * 0.5, 0.0f)):

                    component.buildLog.clear()

                    # Iterate over modules
                    var modules: uint32 = 0
                    for m in component.moduleSelection.items[1]:
                        modules = modules or uint32(parseModuleType(m.name))

                    # Get selected guardrails
                    var guardrails: uint32 = 0
                    if component.domainGuardrailEnabled: guardrails = guardrails or uint32(GUARDRAIL_DOMAIN)
                    if component.ipGuardrailEnabled: guardrails = guardrails or uint32(GUARDRAIL_IP)
                    if component.hostGuardrailEnabled: guardrails = guardrails or uint32(GUARDRAIL_HOSTNAME)

                    result = AgentBuildInformation(
                        listenerId: listeners[component.listener].listenerId,
                        agentType: cast[AgentType](component.agentType),
                        arch: cast[Architecture](component.arch),
                        payloadType: cast[PayloadType](component.payloadType),
                        verbose: component.verbose,
                        sleepSettings: SleepSettings(
                            sleepDelay: component.sleepDelay,
                            jitter: cast[uint32](component.jitter),
                            sleepTechnique: cast[SleepObfuscationTechnique](component.sleepMask),
                            spoofStack: component.spoofStack,
                            workingHours: if component.workingHoursEnabled: component.workingHours else: WorkingHours(enabled: false, startHour: 0, startMinute: 0, endHour: 0, endMinute: 0)
                        ),
                        guardrails : Guardrails(
                            guardrails: guardrails,
                            domain: if component.domainGuardrailEnabled: component.domainGuardrail.toString() else: "",
                            ip: if component.ipGuardrailEnabled: component.ipGuardrail.toString() else: "",
                            hostname: if component.hostGuardrailEnabled: component.hostGuardrail.toString() else: ""
                        ),
                        selfDelete: component.selfDelete,
                        killDate: if component.killDateEnabled: component.killDate else: 0,
                        modules: modules
                    )

                igEndDisabled()
                igSameLine(0.0f, textSpacing)

                if igButton("Close", vec2(availableSize.x * 0.5 - textSpacing * 0.5, 0.0f)):
                    component.resetModalValues()
                    igCloseCurrentPopup()