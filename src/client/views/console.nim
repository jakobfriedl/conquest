import strformat, strutils, times
import imguin/[cimgui, glfw_opengl, simple]
import ../utils/appImGui
import ../../common/[types]

const MAX_INPUT_LENGTH = 512
type    
    ConsoleComponent* = ref object of RootObj
        agent: Agent
        showConsole*: bool
        inputBuffer: array[MAX_INPUT_LENGTH, char]
        console: ConsoleItems
        textSelect: ptr TextSelect

proc getItemText(item: ConsoleItem): cstring = 
    let timestamp = item.timestamp.format("dd-MM-yyyy HH:mm:ss")
    return fmt"[{timestamp}] {$item.itemType} {item.text}".string 

proc getNumLines(data: pointer): csize_t {.cdecl.} =
    if data.isNil:
        return 0
    let console = cast[ConsoleItems](data)
    return console.items.len().csize_t

proc getLineAtIndex(i: csize_t, data: pointer, outLen: ptr csize_t): cstring {.cdecl.} =
    if data.isNil:
        return nil    
    let console = cast[ConsoleItems](data)
    let line = getItemText(console.items[i])
    if not outLen.isNil:
        outLen[] = line.len.csize_t
    return line

proc Console*(agent: Agent): ConsoleComponent =
    result = new ConsoleComponent
    result.agent = agent
    result.showConsole = true
    zeroMem(addr result.inputBuffer[0], MAX_INPUT_LENGTH)

    result.console = new ConsoleItems
    result.console.items = @[]    
    result.textSelect = textselect_create(getLineAtIndex, getNumLines, cast[pointer](result.console), 0)

proc draw*(component: ConsoleComponent) =
    igBegin(fmt"[{component.agent.agentId}] {component.agent.username}@{component.agent.hostname}", addr component.showConsole, 0)
    defer: igEnd()
    
    var focusInput = false

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
    let consolePadding: float = 10.0f 
    let footerHeight = (consolePadding * 2) + (igGetStyle().ItemSpacing.y + igGetFrameHeightWithSpacing())
    let textSpacing = igGetStyle().ItemSpacing.x    

    # Padding 
    igDummy(vec2(0.0f, consolePadding))
    try: 
        # Set styles of the console window
        igPushStyleColor_Vec4(ImGui_Col_FrameBg.int32, vec4(0.1f, 0.1f, 0.1f, 1.0f))
        igPushStyleColor_Vec4(ImGui_Col_ScrollbarBg.int32, vec4(0.1f, 0.1f, 0.1f, 1.0f))
        igPushStyleColor_Vec4(ImGui_Col_Border.int32, vec4(0.2f, 0.2f, 0.2f, 1.0f))
        igPushStyleVar_Float(ImGui_StyleVar_FrameBorderSize .int32, 1.0f)

        let childWindowFlags = ImGuiChildFlags_NavFlattened.int32 or ImGui_ChildFlags_Borders.int32 or ImGui_ChildFlags_AlwaysUseWindowPadding.int32 or ImGuiChildFlags_FrameStyle.int32
        if igBeginChild_Str("##Console", vec2(-1.0f, -footerHeight), childWindowFlags, ImGuiWindowFlags_HorizontalScrollbar.int32):            
            # Display console items
            for entry in component.console.items:
                let timestamp = entry.timestamp.format("dd-MM-yyyy HH:mm:ss")
                igTextColored(vec4(0.6f, 0.6f, 0.6f, 1.0f), fmt"[{timestamp}]".cstring)
                igSameLine(0.0f, textSpacing)
                igTextColored(vec4(0.0f, 1.0f, 1.0f, 1.0f), $entry.itemType)
                igSameLine(0.0f, textSpacing)
                igTextUnformatted(entry.text.cstring, nil)
            
            component.textSelect.textselect_update()
  
            # Auto-scroll to bottom
            if igGetScrollY() >= igGetScrollMaxY():
                igSetScrollHereY(1.0f)
                    
    except IndexDefect:
        # CTRL+A crashes when no items are in the console
        discard
    
    finally: 
        igPopStyleColor(3)
        igPopStyleVar(1)
        igEndChild()
    
    # Padding 
    igDummy(vec2(0.0f, consolePadding))
    
    #[
        Input field with prompt indicator
    ]#
    igText(fmt"[{component.agent.agentId}]") 
    igSameLine(0.0f, textSpacing)
    
    # Calculate available width for input
    var availableWidth: ImVec2
    igGetContentRegionAvail(addr availableWidth)
    igSetNextItemWidth(availableWidth.x)
    
    let inputFlags = ImGuiInputTextFlags_EnterReturnsTrue.int32 or ImGuiInputTextFlags_EscapeClearsAll.int32 # or ImGuiInputTextFlags_CallbackCompletion.int32 or ImGuiInputTextFlags_CallbackHistory.int32
    if igInputText("##Input", addr component.inputBuffer[0], MAX_INPUT_LENGTH, inputFlags, nil, nil):

        let command = $(addr component.inputBuffer[0]).cstring
        let commandItem = ConsoleItem(
            timestamp: now(),
            itemType: LOG_COMMAND,
            text: command
        )
        component.console.items.add(commandItem)

        # TODO: Handle command execution

        zeroMem(addr component.inputBuffer[0], MAX_INPUT_LENGTH)
        focusInput = true
    
    #[
        Session information (optional footer)
    ]#
    # igSeparator()
    # let sessionInfo = fmt"{component.agent.username}@{component.agent.hostname} [{component.agent.ip}]"
    # igText(sessionInfo)
    
    igSetItemDefaultFocus()
    if focusInput: 
        igSetKeyboardFocusHere(-1)
