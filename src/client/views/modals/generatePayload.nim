import strutils
import imguin/[cimgui, glfw_opengl, simple]
import ../../utils/appImGui
import ../../../common/[types, utils]


type 
    AgentModalComponent* = ref object of RootObj
        listener: int32 
        sleepDelay: uint32 
        sleepMask: int32 
        spoofStack: bool 
        listeners: seq[string]
        sleepMaskTechniques: seq[string]

proc AgentModal*(listeners: seq[Listener]): AgentModalComponent =
    result = new AgentModalComponent
    result.listener = 0
    result.sleepDelay = 5
    result.sleepMask = 0
    result.spoofStack = false

    for l in listeners: 
        result.listeners.add(l.listenerId)

    for s in SleepObfuscationTechnique.low .. SleepObfuscationTechnique.high:
        result.sleepMaskTechniques.add($s)

proc resetModalValues(component: AgentModalComponent) = 
    discard 

proc draw*(component: AgentModalComponent) =
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
        igCombo_Str("##InputListener", addr component.listener, (component.listeners.join("\0") & "\0").cstring , component.listeners.len().int32)

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
        


        igGetContentRegionAvail(addr availableSize)

        igDummy(vec2(0.0f, 10.0f))
        igSeparator()
        igDummy(vec2(0.0f, 10.0f))

        if igButton("Build", vec2(availableSize.x * 0.5 - textSpacing * 0.5, 0.0f)):
            
            
            component.resetModalValues()
            igCloseCurrentPopup() 
        
        igSameLine(0.0f, textSpacing)

        if igButton("Close", vec2(availableSize.x * 0.5 - textSpacing * 0.5, 0.0f)):
            component.resetModalValues()
            igCloseCurrentPopup()