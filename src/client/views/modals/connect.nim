import whisky, strutils, strformat
import imguin/[cimgui, glfw_opengl]
import ../../utils/[appImGui, globals]
import ../../../common/utils
import ../../../types/[common, client]

proc ConnectionModal*(host: string, port: int): ConnectionModalComponent =
    result = new ConnectionModalComponent
    
    zeroMem(addr result.host[0], 256)
    for i, c in host: 
        if i < 255: result.host[i] = c
    result.defaultHost = host

    result.port = uint16(port)
    result.defaultPort = port
    
    zeroMem(addr result.usernameInput[0], 256)
    zeroMem(addr result.passwordInput[0], 256)
    result.errorMessage = ""

proc resetModalValues(component: ConnectionModalComponent) = 
    zeroMem(addr component.host[0], 256)
    for i, c in component.defaultHost: 
        if i < 255: component.host[i] = c
    component.port = uint16(component.defaultPort)
    zeroMem(addr component.usernameInput[0], 256)
    zeroMem(addr component.passwordInput[0], 256)

proc connect*(component: ConnectionModalComponent) = 
    component.errorMessage = ""

    let host = $cast[cstring]((addr component.host[0]))
    component.username = $cast[cstring]((addr component.usernameInput[0]))
    component.password = $cast[cstring]((addr component.passwordInput[0]))

    try: 
        cq.connection = WsConnection(
            ws: newWebSocket(fmt"ws://{host}:{$component.port}"),
            sessionKey: default(Key)
        )    
    except OSError:
        component.errorMessage = "Cannot connect to team server."

    component.resetModalValues()

proc draw*(component: ConnectionModalComponent) =
    let textSpacing = igGetStyle().ItemSpacing.x    
    
    # Center modal
    let vp = igGetMainViewport()
    var center: ImVec2
    ImGuiViewport_GetCenter(addr center, vp)
    igSetNextWindowPos(center, ImGuiCond_Always.int32, vec2(0.5f, 0.5f))

    let modalWidth = max(500.0f, vp.Size.x * 0.25)
    igSetNextWindowSize(vec2(modalWidth, 0.0f), ImGuiCond_Always.int32)
    
    var show = true
    if igBeginPopupModal("Connect", addr show, ImGuiWindowFlags_NoMove.int32):
        defer: igEndPopup()
        
        var availableSize: ImVec2

        # Team server IP address
        igText("Host:     ")
        igSameLine(0.0f, textSpacing)
        igGetContentRegionAvail(addr availableSize)
        igSetNextItemWidth(availableSize.x)
        igInputText("##InputHost", cast[cstring](addr component.host[0]), 256, ImGui_InputTextFlags_CharsNoBlank.int32, nil, nil)

        # Team server port
        let step: uint16 = 1
        igText("Port:     ")
        igSameLine(0.0f, textSpacing)
        igSetNextItemWidth(availableSize.x)
        igInputScalar("##InputPort", ImGuiDataType_U16.int32, addr component.port, addr step, nil, "%hu", ImGui_InputTextFlags_CharsDecimal.int32)

        # Username
        igText("Username: ")
        igSameLine(0.0f, textSpacing)
        igGetContentRegionAvail(addr availableSize)
        igSetNextItemWidth(availableSize.x)
        if igIsWindowAppearing(): igSetKeyboardFocusHere(0)
        igInputText("##InputUsername", cast[cstring](addr component.usernameInput[0]), 256, ImGui_InputTextFlags_CharsNoBlank.int32, nil, nil)

        # Password
        igText("Password: ")
        igSameLine(0.0f, textSpacing)
        igGetContentRegionAvail(addr availableSize)
        igSetNextItemWidth(availableSize.x)
        if igInputText("##InputPassword", cast[cstring](addr component.passwordInput[0]), 256, ImGuiInputTextFlags_EnterReturnsTrue.int32 or ImGui_InputTextFlags_Password.int32, nil, nil): 
            component.connect()
            igCloseCurrentPopup() 
        
        # Display error message
        if component.errorMessage.len() > 0:
            igDummy(vec2(0.0f, 10.0f))
            igTextColored(CONSOLE_ERROR, (" ".repeat(11) & ICON_FA_TRIANGLE_EXCLAMATION & " " & component.errorMessage).cstring)

        # Only enable the button when required fields have been filled in
        igBeginDisabled(
            ($cast[cstring]((addr component.host[0])) == "") or 
            (component.port <= 0) or
            ($cast[cstring]((addr component.usernameInput[0])) == "")
        )

        igGetContentRegionAvail(addr availableSize)

        igDummy(vec2(0.0f, 10.0f))
        igSeparator()
        igDummy(vec2(0.0f, 10.0f))

        if igButton("Connect", vec2(availableSize.x, 0.0f)): 
            component.connect()
            igCloseCurrentPopup() 
        
        igEndDisabled()
        igSameLine(0.0f, textSpacing)
