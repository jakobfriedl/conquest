import strformat, strutils
import imguin/[cimgui, glfw_opengl, simple]
import ../utils/appImGui
import ../../common/[types]

type 
    ConsoleComponent* = ref object of RootObj
        agent: Agent
        showConsole*: bool
        inputBuffer: string
        consoleEntries: seq[string]
        console: ptr TextEditor

proc Console*(agent: Agent): ConsoleComponent = 
    result = new ConsoleComponent
    result.agent = agent
    result.showConsole = true
    result.console = TextEditor_TextEditor()
    result.consoleEntries = @[
        "a",
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    ]

    result.console.TextEditor_SetText(result.consoleEntries.join("\n") & '\0')

proc findLongestLength(text: string): float32 =
    var maxWidth = 0.0f
    for line in text.splitLines():
        let line_cstring = line.cstring
        var textSizeOut: ImVec2
        igCalcTextSize(addr textSizeOut, line_cstring, nil, false, -1.0f)
        if textSizeOut.x > maxWidth:
            maxWidth = textSizeOut.x
    return maxWidth

proc draw*(component: ConsoleComponent) = 

    igBegin(fmt"[{component.agent.agentId}] {component.agent.username}@{component.agent.hostname}", addr component.showConsole, 0)
    defer: igEnd() 

    # Console text section
    # A InputTextMultiline component is placed within a Child Frame to enable both proper text selection and a horizontal scrollbar
    # The only thing missing from this implementation is the ability change the text color
    # https://github.com/ocornut/imgui/issues/383#issuecomment-2080346129
    let footerHeight = igGetStyle().ItemSpacing.y + igGetFrameHeightWithSpacing()
    let buffer = component.consoleEntries.join("\n") & '\0'
    
    # Push styles to hide the Child's background and scrollbar background.
    igPushStyleColor_Vec4(ImGuiCol_FrameBg.int32, vec4(0.0f, 0.0f, 0.0f, 0.0f))
    igPushStyleColor_Vec4(ImGuiCol_ScrollbarBg.int32, vec4(0.0f, 0.0f, 0.0f, 0.0f))

    if igBeginChild_Str("##Console", vec2(-0.99f, -footerHeight), ImGuiChildFlags_NavFlattened.int32, ImGuiWindowFlags_HorizontalScrollbar.int32):

        # Manually handle horizontal scrolling with the mouse wheel/touchpad
        let io = igGetIO()
        if io.MouseWheelH != 0:
            let scroll_delta = io.MouseWheelH * igGetScrollX() * 0.5
            igSetScrollX_Float(igGetScrollX() - scroll_delta)
            if igGetScrollX() == 0:
                igSetScrollX_Float(1.0f) # This is required to prevent the horizontal scrolling from snapping in

        # Retrieve the length of the longes console entry
        var width = findLongestLength(buffer) 
        if width <= io.DisplaySize.x: 
            width = -1.0f

        # Set the Text edit background color and make it visible.
        igPushStyleColor_Vec4(ImGuiCol_FrameBg.int32, vec4(0.1f, 0.1f, 0.1f, 1.0f))
        igPushStyleColor_Vec4(ImGuiCol_ScrollbarBg.int32, vec4(0.1f, 0.1f, 0.1f, 1.0f))
        discard igInputTextMultiline("##ConsoleText", buffer, cast[csize_t](buffer.len()), vec2(width, -1.0f), ImGui_InputTextFlags_ReadOnly.int32 or ImGui_InputTextFlags_AllowTabInput.int32, nil, nil)
        
        # Alternative: ImGuiColorTextEdit
        # component.console.TextEditor_SetReadOnlyEnabled(true)
        # component.console.TextEditor_SetShowLineNumbersEnabled(false)
        # component.console.TextEditor_Render("##ConsoleEntries", false, vec2(-1, -1), true)
        
        igPopStyleColor(2)

    igPopStyleColor(2)
    igEndChild()

    igSeparator()

    # Input field
    igSetNextItemWidth(-1.0f)
    let inputFlags = ImGuiInputTextFlags_EnterReturnsTrue.int32 or ImGuiInputTextFlags_EscapeClearsAll.int32 or ImGuiInputTextFlags_CallbackCompletion.int32 or ImGuiInputTextFlags_CallbackHistory.int32
    if igInputText("##Input", component.inputBuffer, 256, inputFlags, nil, nil): 
        discard

    igSetItemDefaultFocus()
