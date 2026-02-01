import strformat, strutils
import imguin/[cimgui, glfw_opengl]
import ./widgets/textarea
import ../utils/[appImGui, globals]
import ../core/websocket
import ../../types/[client, event]
export addItem

proc Chat*(title: string, showComponent: ptr bool): ChatComponent = 
    result = new ChatComponent
    result.title = title
    result.showComponent = showComponent
    result.textarea = Textarea()
    zeroMem(addr result.inputBuffer[0], MAX_INPUT_LENGTH)

proc draw*(component: ChatComponent) = 
    igBegin(component.title.cstring, component.showComponent, 0)
    defer: igEnd() 

    var focusInput: bool = false
    let consolePadding: float = 10.0f 
    let footerHeight = (consolePadding * 2) + (igGetStyle().ItemSpacing.y + igGetFrameHeightWithSpacing()) * 0.75f
    let textSpacing = igGetStyle().ItemSpacing.x    

    component.textarea.draw(vec2(-1.0f, -footerHeight))
    igDummy(vec2(0.0f, consolePadding))

    igText(fmt"[{cq.connection.user}]".cstring) 
    igSameLine(0.0f, textSpacing)    

    var availableSize: ImVec2
    igGetContentRegionAvail(addr availableSize)
    igSetNextItemWidth(availableSize.x)
    
    let inputFlags = ImGuiInputTextFlags_EnterReturnsTrue.int32 or ImGuiInputTextFlags_EscapeClearsAll.int32
    if igInputText("##Input", cast[cstring](addr component.inputBuffer[0]), MAX_INPUT_LENGTH, inputFlags, nil, nil):
        let message = ($cast[cstring]((addr component.inputBuffer[0]))).strip()
        
        # Send chat message
        cq.connection.sendChatMessage(message)

        zeroMem(addr component.inputBuffer[0], MAX_INPUT_LENGTH)
        focusInput = true
    
    igSetItemDefaultFocus()
    if focusInput: 
        igSetKeyboardFocusHere(-1)