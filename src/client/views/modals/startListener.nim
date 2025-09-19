import strutils
import imguin/[cimgui, glfw_opengl, simple]
import ../../utils/appImGui
import ../../../common/[types, utils]

const DEFAULT_PORT = 8080'u16

type 
    ListenerModalComponent* = ref object of RootObj
        address: array[256, char]
        port: uint16 
        protocol: int32
        protocols: seq[string]

proc ListenerModal*(): ListenerModalComponent =
    result = new ListenerModalComponent
    zeroMem(addr result.address[0], 256)
    result.port = DEFAULT_PORT
    result.protocol = 0
    for p in Protocol.low .. Protocol.high:
        result.protocols.add($p)

proc resetModalValues(component: ListenerModalComponent) = 
    zeroMem(addr component.address[0], 256)
    component.port = DEFAULT_PORT
    component.protocol = 0

proc draw*(component: ListenerModalComponent): Listener =
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
    if igBeginPopupModal("Start Listener", addr show, windowFlags):
        defer: igEndPopup()
        
        var availableSize: ImVec2
        igGetContentRegionAvail(addr availableSize)

        # Listener address 
        igText("Host:     ")
        igSameLine(0.0f, textSpacing)
        igGetContentRegionAvail(addr availableSize)
        igSetNextItemWidth(availableSize.x)
        igInputTextWithHint("##InputAddress", "127.0.0.1", addr component.address[0], 256, ImGui_InputTextFlags_CharsNoBlank.int32, nil, nil)

        # Listener port 
        let step: uint16 = 1
        igText("Port:     ")
        igSameLine(0.0f, textSpacing)
        igSetNextItemWidth(availableSize.x)
        igInputScalar("##InputPort", ImGuiDataType_U16.int32, addr component.port, addr step, nil, "%hu", ImGui_InputTextFlags_CharsDecimal.int32)

        # Listener protocol dropdown selection
        igText("Protocol: ")
        igSameLine(0.0f, textSpacing)
        igSetNextItemWidth(availableSize.x)
        igCombo_Str("##InputProtocol", addr component.protocol, (component.protocols.join("\0") & "\0").cstring , component.protocols.len().int32)

        igGetContentRegionAvail(addr availableSize)

        igDummy(vec2(0.0f, 10.0f))
        igSeparator()
        igDummy(vec2(0.0f, 10.0f))

        # Only enabled the start button when valid values have been entered
        igBeginDisabled(($(addr component.address[0]) == "") or (component.port <= 0))

        if igButton("Start", vec2(availableSize.x * 0.5 - textSpacing * 0.5, 0.0f)):
            
            result = Listener(
                listenerId: generateUUID(),
                address: $(addr component.address[0]),
                port: int(component.port),
                protocol: cast[Protocol](component.protocol)
            )
            component.resetModalValues()
            igCloseCurrentPopup() 
        
        igEndDisabled()
        igSameLine(0.0f, textSpacing)

        if igButton("Close", vec2(availableSize.x * 0.5 - textSpacing * 0.5, 0.0f)):
            
            component.resetModalValues()
            igCloseCurrentPopup()