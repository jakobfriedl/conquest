import strutils
import imguin/[cimgui, glfw_opengl, simple]
import ../../utils/appImGui
import ../../../common/[types, utils]

const DEFAULT_PORT = 8080'u16

type 
    ListenerModalComponent* = ref object of RootObj
        callbackHosts: array[256 * 32, char]
        bindAddress: array[256, char]
        bindPort: uint16 
        protocol: int32
        protocols: seq[string]

proc ListenerModal*(): ListenerModalComponent =
    result = new ListenerModalComponent
    zeroMem(addr result.callbackHosts[0], 256 * 32)
    zeroMem(addr result.bindAddress[0], 256)
    result.bindPort = DEFAULT_PORT
    result.protocol = 0
    for p in Protocol.low .. Protocol.high:
        result.protocols.add($p)

proc resetModalValues(component: ListenerModalComponent) = 
    zeroMem(addr component.callbackHosts[0], 256 * 32)
    zeroMem(addr component.bindAddress[0], 256)
    component.bindPort = DEFAULT_PORT
    component.protocol = 0

proc draw*(component: ListenerModalComponent): UIListener =
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

        # Listener protocol/type dropdown selection
        igText("Protocol:         ")
        igSameLine(0.0f, textSpacing)
        igGetContentRegionAvail(addr availableSize)
        igSetNextItemWidth(availableSize.x)
        igCombo_Str("##InputProtocol", addr component.protocol, (component.protocols.join("\0") & "\0").cstring , component.protocols.len().int32)
        
        igDummy(vec2(0.0f, 10.0f))
        igSeparator()
        igDummy(vec2(0.0f, 10.0f))

        # HTTP Listener settings
        if component.protocols[component.protocol] == $HTTP:
            # Listener bindAddress 
            igText("Host (Bind):      ")
            igSameLine(0.0f, textSpacing)
            igGetContentRegionAvail(addr availableSize)
            igSetNextItemWidth(availableSize.x)
            igInputTextWithHint("##InputAddressBind", "0.0.0.0", addr component.bindAddress[0], 256, ImGui_InputTextFlags_CharsNoBlank.int32, nil, nil)

            # Listener bindPort 
            let step: uint16 = 1
            igText("Port (Bind):      ")
            igSameLine(0.0f, textSpacing)
            igSetNextItemWidth(availableSize.x)
            igInputScalar("##InputPortBind", ImGuiDataType_U16.int32, addr component.bindPort, addr step, nil, "%hu", ImGui_InputTextFlags_CharsDecimal.int32)

            # Callback hosts
            igText("Hosts (Callback): ")
            igSameLine(0.0f, textSpacing)
            igGetContentRegionAvail(addr availableSize)
            igSetNextItemWidth(availableSize.x)
            igInputTextMultiline("##InputCallbackHosts", addr component.callbackHosts[0], 256 * 32, vec2(0.0f, 3.0f * igGetTextLineHeightWithSpacing()), ImGui_InputTextFlags_CharsNoBlank.int32, nil, nil)
      
        igGetContentRegionAvail(addr availableSize)

        igDummy(vec2(0.0f, 10.0f))
        igSeparator()
        igDummy(vec2(0.0f, 10.0f))

        # Only enabled the start button when valid values have been entered
        igBeginDisabled(($(addr component.bindAddress[0]) == "") or (component.bindPort <= 0))

        if igButton("Start", vec2(availableSize.x * 0.5 - textSpacing * 0.5, 0.0f)): 

            # Process input values
            var hosts: string = ""
            let 
                callbackHosts = $(addr component.callbackHosts[0])
                bindAddress = $(addr component.bindAddress[0])
                bindPort =  int(component.bindPort)

            if callbackHosts.isEmptyOrWhitespace(): 
                hosts &= bindAddress & ":"  & $bindPort

            else: 
                for host in callbackHosts.splitLines():
                    hosts &= ";"
                    let hostParts = host.split(":")
                    if hostParts.len() == 2:
                        if not hostParts[1].isEmptyOrWhitespace():  
                            hosts &= hostParts[0] & ":" & hostParts[1]
                        else: 
                            hosts &= hostParts[0] & ":" & $bindPort
                    elif hostParts.len() == 1 and not hostParts[0].isEmptyOrWhitespace(): 
                        hosts &= hostParts[0] & ":" & $bindPort
            
                hosts.removePrefix(";")

            # Return new listener object
            result = UIListener(
                listenerId: generateUUID(),
                hosts: hosts,
                address: bindAddress,
                port: bindPort,
                protocol: cast[Protocol](component.protocol)
            )
            component.resetModalValues()
            igCloseCurrentPopup() 
        
        igEndDisabled()
        igSameLine(0.0f, textSpacing)

        if igButton("Close", vec2(availableSize.x * 0.5 - textSpacing * 0.5, 0.0f)):
            component.resetModalValues()
            igCloseCurrentPopup()