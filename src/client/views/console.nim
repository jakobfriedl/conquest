import strformat, strutils, times
import imguin/[cimgui, glfw_opengl, simple]
import ../utils/appImGui
import ../../common/[types]

type
    ConsoleItem = ref object 
        timestamp: DateTime
        logType: LogType
        text: string

    ConsoleItems = ref object
        items: seq[string]
    
    ConsoleComponent* = ref object of RootObj
        agent: Agent
        showConsole*: bool
        inputBuffer: string
        consoleItems: ConsoleItems
        textSelect: ptr TextSelect

proc getNumLines(data: pointer): csize_t {.cdecl.} =
    if data.isNil:
        return 0
    let consoleItems = cast[ConsoleItems](data)
    return consoleItems.items.len().csize_t

proc getLineAtIndex(i: csize_t, data: pointer, outLen: ptr csize_t): cstring {.cdecl.} =
    if data.isNil:
        return nil    
    let consoleItems = cast[ConsoleItems](data)
    let line = consoleItems.items[i].cstring    
    if not outLen.isNil:
        outLen[] = line.len.csize_t
    return line

proc Console*(agent: Agent): ConsoleComponent =
    result = new ConsoleComponent
    result.agent = agent
    result.showConsole = true
    result.inputBuffer = ""

    result.consoleItems = new ConsoleItems
    result.consoleItems.items = @[]    
    result.textSelect = textselect_create(getLineAtIndex, getNumLines, cast[pointer](result.consoleItems), 0)

proc draw*(component: ConsoleComponent) =
    igBegin(fmt"[{component.agent.agentId}] {component.agent.username}@{component.agent.hostname}", addr component.showConsole, 0)
    defer: igEnd()
    
    #[
        Console items/text section using ImGuiTextSelect in a child window
        Supports: 
            - horizontal+vertical scrolling,
            - autoscroll
            - colored text
            - text selection and copy functionality

        Problems I encountered with other approaches (Multi-line Text Input, TextEditor, ...):
        - https://github.com/ocornut/imgui/issues/383#issuecomment-2080346129
        - https://github.com/ocornut/imgui/issues/950
        Huge thanks to @dinau for implementing ImGuiTextSelect into imguin very rapidly after I requested it.
    ]#
    let footerHeight = igGetStyle().ItemSpacing.y + igGetFrameHeightWithSpacing() * 2
    
    if igBeginChild_Str("##Console", vec2(-1.0f, -footerHeight), ImGuiChildFlags_NavFlattened.int32, ImGuiWindowFlags_HorizontalScrollbar.int32):
        
        # Display console items
        for entry in component.consoleItems.items:
            igTextColored(vec4(0.0f, 1.0f, 1.0f, 1.0f), entry.cstring)
        
        component.textSelect.textselect_update()
        
        # Auto-scroll to bottom if we're already at the bottom
        if igGetScrollY() >= igGetScrollMaxY():
            igSetScrollHereY(1.0f)
    
    igEndChild()
    
    # Buttons for testing the console 
    if igButton("Add Items", vec2(0.0f, 0.0f)):
        for i in 1..10:
            component.consoleItems.items.add("Hello world!")

    igSameLine(0.0f, 5.0f)
    if igButton("Add Long Items", vec2(0.0f, 0.0f)):
        for i in 1..3:
            component.consoleItems.items.add("Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor invidunt ut labore et dolore magna aliquyam erat, sed diam voluptua. At vero eos et accusam et justo duo dolores et ea rebum. Stet clita kasd gubergren, no sea takimata sanctus est Lorem ipsum dolor sit amet. Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor invidunt ut labore et dolore magna aliquyam erat, sed diam voluptua. At vero eos et accusam et justo duo dolores et ea rebum. Stet clita kasd gubergren, no sea takimata sanctus est Lorem ipsum dolor sit amet.")
    
    igSameLine(0.0f, 5.0f)
    if igButton("Clear", vec2(0.0f, 0.0f)):
        component.consoleItems.items.setLen(0)

    #[
        Input field with prompt indicator
    ]#
    igText(fmt"[{component.agent.agentId}]") 
    let spacing = igGetStyle().ItemSpacing.x    
    igSameLine(0.0f, spacing)
    
    # Calculate available width for input
    var availableWidth: ImVec2
    igGetContentRegionAvail(addr availableWidth)
    igSetNextItemWidth(availableWidth.x)
    
    let inputFlags = ImGuiInputTextFlags_EnterReturnsTrue.int32 or ImGuiInputTextFlags_EscapeClearsAll.int32 or ImGuiInputTextFlags_CallbackCompletion.int32 or ImGuiInputTextFlags_CallbackHistory.int32
    if igInputText("##Input", component.inputBuffer, 256, inputFlags, nil, nil):
        discard
    
    #[
        Session information (optional footer)
    ]#
    # igSeparator()
    # let sessionInfo = fmt"{component.agent.username}@{component.agent.hostname} [{component.agent.ip}]"
    # igText(sessionInfo)
    
    igSetItemDefaultFocus()
