import whisky
import strformat, strutils, times, json, tables, sequtils
import imguin/[cimgui, glfw_opengl, simple]
import ../utils/[appImGui, colors]
import ../../common/[types, utils]
import ../../modules/manager
import ../[task, websocket]

const MAX_INPUT_LENGTH = 512
type 
    ConsoleComponent* = ref object of RootObj
        agent*: UIAgent
        showConsole*: bool
        inputBuffer: array[MAX_INPUT_LENGTH, char]
        console*: ConsoleItems
        history: seq[string]
        historyPosition: int 
        currentInput: string
        textSelect: ptr TextSelect
        filter: ptr ImGuiTextFilter

#[
    Helper functions for text selection
]#
proc getText(item: ConsoleItem): cstring = 
    if item.timestamp > 0: 
        let timestamp = item.timestamp.fromUnix().format("dd-MM-yyyy HH:mm:ss")
        return fmt"[{timestamp}]{$item.itemType}{item.text}".string 
    else: 
        return fmt"{$item.itemType}{item.text}".string 

proc getNumLines(data: pointer): csize_t {.cdecl.} =
    if data.isNil:
        return 0
    let console = cast[ConsoleItems](data)
    return console.items.len().csize_t

proc getLineAtIndex(i: csize_t, data: pointer, outLen: ptr csize_t): cstring {.cdecl.} =
    if data.isNil:
        return nil    
    let console = cast[ConsoleItems](data)
    let line = console.items[i].getText()
    if not outLen.isNil:
        outLen[] = line.len.csize_t
    return line

proc Console*(agent: UIAgent): ConsoleComponent =
    result = new ConsoleComponent
    result.agent = agent
    result.showConsole = true
    zeroMem(addr result.inputBuffer[0], MAX_INPUT_LENGTH)
    result.console = new ConsoleItems
    result.console.items = @[]
    result.history = @[]
    result.historyPosition = -1  
    result.currentInput = ""
    result.textSelect = textselect_create(getLineAtIndex, getNumLines, cast[pointer](result.console), 0)
    result.filter = ImGuiTextFilter_ImGuiTextFilter("")

#[
    Text input callback function for managing console history and autocompletion 
]#
proc callback(data: ptr ImGuiInputTextCallbackData): cint {.cdecl.} = 

    let component = cast[ConsoleComponent](data.UserData)
    
    case data.EventFlag: 
    of ImGui_InputTextFlags_CallbackHistory.int32:     
        # Handle command history using arrow-keys 

        # Store current input
        if component.historyPosition == -1: 
            component.currentInput = $(data.Buf)        

        let prev = component.historyPosition

        # Move to a new console history item
        if data.EventKey == ImGuiKey_UpArrow:
            if component.history.len() > 0:
                if component.historyPosition < 0: # We are at the current input and move to the last item in the console history
                    component.historyPosition = component.history.len() - 1 
                else: 
                    component.historyPosition = max(0, component.historyPosition - 1)

        elif data.EventKey == ImGuiKey_DownArrow: 
            if component.historyPosition != -1:
                component.historyPosition = min(component.history.len(), component.historyPosition + 1)
            
            if component.historyPosition == component.history.len(): 
                component.historyPosition = -1

        # Update the text buffer if another item was selected
        if prev != component.historyPosition: 
            let newText = if component.historyPosition == -1:
                component.currentInput
            else:
                component.history[component.historyPosition]

            # Replace text input
            data.ImGuiInputTextCallbackData_DeleteChars(0, data.BufTextLen)
            data.ImGuiInputTextCallbackData_InsertChars(0, newText.cstring, nil)

            # Set the cursor to the end of the updated input text
            data.CursorPos = newText.len().cint 
            data.SelectionStart = newText.len().cint
            data.SelectionEnd = newText.len().cint

        return 0

    of ImGui_InputTextFlags_CallbackCompletion.int32: 
        # Handle Tab-autocompletion
        discard

    else: discard

#[
    API to add new console item
]#
proc addItem*(component: ConsoleComponent, itemType: LogType, data: string, timestamp: int64 = now().toTime().toUnix()) = 

    for line in data.split("\n"): 
        component.console.items.add(ConsoleItem(
            timestamp: if itemType == LOG_OUTPUT: 0 else: timestamp,
            itemType: itemType,
            text: line
        ))

#[
    Handling console commands
]#
proc displayHelp(component: ConsoleComponent) = 
    for module in getModules(component.agent.modules): 
        for cmd in module.commands: 
            component.addItem(LOG_OUTPUT, fmt" * {cmd.name:<15}{cmd.description}")

proc displayCommandHelp(component: ConsoleComponent, command: Command) = 
    var usage = command.name & " " & command.arguments.mapIt(
        if it.isRequired: fmt"<{it.name}>" else: fmt"[{it.name}]"
    ).join(" ")

    if command.example != "": 
        usage &= "\nExample : " & command.example

    component.addItem(LOG_OUTPUT, fmt"""
{command.description}

Usage   : {usage}
""")

    if command.arguments.len > 0:
        component.addItem(LOG_OUTPUT, "Arguments:\n")

        let header = @["Name", "Type", "Required", "Description"]
        component.addItem(LOG_OUTPUT, fmt"   {header[0]:<15} {header[1]:<6} {header[2]:<8} {header[3]}")
        component.addItem(LOG_OUTPUT, fmt"   {'-'.repeat(15)} {'-'.repeat(6)} {'-'.repeat(8)} {'-'.repeat(20)}")
        
        for arg in command.arguments: 
            let isRequired = if arg.isRequired: "YES" else: "NO"
            component.addItem(LOG_OUTPUT, fmt" * {arg.name:<15} {($arg.argumentType).toUpperAscii():<6} {isRequired:>8} {arg.description}")
        component.addItem(LOG_OUTPUT, "")

proc handleHelp(component: ConsoleComponent, parsed: seq[string]) = 
    try: 
        # Try parsing the first argument passed to 'help' as a command
        component.displayCommandHelp(getCommandByName(parsed[1]))
    except IndexDefect:
        # 'help' command is called without additional parameters
        component.displayHelp()
    except ValueError: 
        # Command was not found
        component.addItem(LOG_ERROR, fmt"The command '{parsed[1]}' does not exist.")

proc handleAgentCommand*(component: ConsoleComponent, connection: WsConnection, input: string) = 

    # Convert user input into sequence of string arguments
    let parsedArgs = parseInput(input)
    
    # Handle 'help' command 
    if parsedArgs[0] == "help": 
        component.handleHelp(parsedArgs)
        return
        
    # Handle commands with actions on the agent
    try: 
        let 
            command = getCommandByName(parsedArgs[0])
            task = createTask(component.agent.agentId, component.agent.listenerId, command, parsedArgs[1..^1])

        connection.sendAgentTask(component.agent.agentId, task)
        component.addItem(LOG_INFO, fmt"Tasked agent to {command.description.toLowerAscii()} ({Uuid.toString(task.taskId)})")

    except CatchableError: 
        component.addItem(LOG_ERROR, getCurrentExceptionMsg())

#[
    Drawing
]#
proc print(item: ConsoleItem) =     
    
    if item.timestamp > 0:
        let timestamp = item.timestamp.fromUnix().format("dd-MM-yyyy HH:mm:ss")
        igTextColored(vec4(0.6f, 0.6f, 0.6f, 1.0f), fmt"[{timestamp}]".cstring)
        igSameLine(0.0f, 0.0f)
    
    case item.itemType:
    of LOG_INFO, LOG_INFO_SHORT: 
        igTextColored(CONSOLE_INFO, $item.itemType)
    of LOG_ERROR, LOG_ERROR_SHORT: 
        igTextColored(CONSOLE_ERROR, $item.itemType)
    of LOG_SUCCESS, LOG_SUCCESS_SHORT: 
        igTextColored(CONSOLE_SUCCESS, $item.itemType)
    of LOG_WARNING, LOG_WARNING_SHORT: 
        igTextColored(CONSOLE_WARNING, $item.itemType)
    of LOG_COMMAND: 
        igTextColored(CONSOLE_COMMAND, $item.itemType)
    of LOG_OUTPUT: 
        igTextColored(vec4(0.0f, 0.0f, 0.0f, 0.0f), $item.itemType)

    igSameLine(0.0f, 0.0f)
    igTextUnformatted(item.text.cstring, nil)

proc draw*(component: ConsoleComponent, connection: WsConnection) =
    igBegin(fmt"[{component.agent.agentId}] {component.agent.username}@{component.agent.hostname}".cstring, addr component.showConsole, 0)
    defer: igEnd()
    
    let io = igGetIO()

    var focusInput = false

    #[
        Console items/text section using ImGuiTextSelect in a child window
        Features: 
            - Horizontal+vertical scrolling,
            - Autoscroll
            - Colored text output
            - Text highlighting, copy/paste

        Problems I encountered with other approaches (Multi-line Text Input, TextEditor, ...):
            - https://github.com/ocornut/imgui/issues/383#issuecomment-2080346129
            - https://github.com/ocornut/imgui/issues/950
        
        Huge thanks to @dinau for implementing ImGuiTextSelect into imguin very rapidly after I requested it.
    ]#
    let consolePadding: float = 10.0f 
    let footerHeight = (consolePadding * 2) + (igGetStyle().ItemSpacing.y + igGetFrameHeightWithSpacing()) * 0.75f
    let textSpacing = igGetStyle().ItemSpacing.x    

    # Padding 
    igDummy(vec2(0.0f, consolePadding))
    
    #[
        Session information
    ]#
    let domain = if component.agent.domain.isEmptyOrWhitespace(): "" else: fmt".{component.agent.domain}"
    let sessionInfo = fmt"{component.agent.username}@{component.agent.hostname}{domain} | {component.agent.ipInternal} | {$component.agent.pid}/{component.agent.process}".cstring
    igTextColored(GRAY, sessionInfo)
    igSameLine(0.0f, 0.0f)

    #[
        Filter & Options
    ]# 
    var availableSize: ImVec2
    igGetContentRegionAvail(addr availableSize)
    var labelSize: ImVec2
    igCalcTextSize(addr labelSize, ICON_FA_MAGNIFYING_GLASS, nil, false, 0.0f)
    
    let searchBoxWidth: float32 = 200.0f
    igSameLine(0.0f, availableSize.x  - (labelSize.x + textSpacing) - searchBoxWidth)

    # Show tooltip when hovering the search icon
    igTextUnformatted(ICON_FA_MAGNIFYING_GLASS.cstring, nil)
    if igIsItemHovered(ImGuiHoveredFlags_None.int32):
        igBeginTooltip()
        igText("Press CTRL+F to focus console filter.")
        igText("Use \",\" as a delimiter to filter for multiple values.")
        igText("Use \"-\" to exclude values.")
        igText("Example: \"-warning,a,b\" returns all lines that do not include \"warning\" but include either \"a\" or \"b\".")
        igEndTooltip()

    if igIsWindowFocused(ImGui_FocusedFlags_ChildWindows.int32) and io.KeyCtrl and igIsKeyPressed_Bool(ImGuiKey_F, false):
        igSetKeyboardFocusHere(0) 

    igSameLine(0.0f, textSpacing)
    component.filter.ImGuiTextFilter_Draw("##ConsoleSearch", searchBoxWidth)    

    try: 
        # Set styles of the console window
        igPushStyleColor_Vec4(ImGui_Col_FrameBg.int32, vec4(0.1f, 0.1f, 0.1f, 1.0f))
        igPushStyleColor_Vec4(ImGui_Col_ScrollbarBg.int32, vec4(0.1f, 0.1f, 0.1f, 1.0f))
        igPushStyleColor_Vec4(ImGui_Col_Border.int32, vec4(0.2f, 0.2f, 0.2f, 1.0f))
        igPushStyleVar_Float(ImGui_StyleVar_FrameBorderSize .int32, 1.0f)

        let childWindowFlags = ImGuiChildFlags_NavFlattened.int32 or ImGui_ChildFlags_Borders.int32 or ImGui_ChildFlags_AlwaysUseWindowPadding.int32 or ImGuiChildFlags_FrameStyle.int32
        if igBeginChild_Str("##Console", vec2(-1.0f, -footerHeight), childWindowFlags, ImGuiWindowFlags_HorizontalScrollbar.int32):            
                        
            # Display console items
            for item in component.console.items:

                # Apply filter
                if component.filter.ImGuiTextFilter_IsActive():
                    if not component.filter.ImGuiTextFilter_PassFilter(item.getText(), nil):
                        continue
                
                item.print()    

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
    igGetContentRegionAvail(addr availableSize)
    igSetNextItemWidth(availableSize.x)
    
    let inputFlags = ImGuiInputTextFlags_EnterReturnsTrue.int32 or ImGuiInputTextFlags_EscapeClearsAll.int32 or ImGuiInputTextFlags_CallbackHistory.int32 or ImGuiInputTextFlags_CallbackCompletion.int32
    if igInputText("##Input", addr component.inputBuffer[0], MAX_INPUT_LENGTH, inputFlags, callback, cast[pointer](component)):

        let command = ($(addr component.inputBuffer[0])).strip()
        if not command.isEmptyOrWhitespace(): 

            component.addItem(LOG_COMMAND, command)

            # Send command to team server
            component.handleAgentCommand(connection, command)

            # Add command to console history
            component.history.add(command)
            component.historyPosition = -1 

        zeroMem(addr component.inputBuffer[0], MAX_INPUT_LENGTH)
        focusInput = true
    
    igSetItemDefaultFocus()
    if focusInput: 
        igSetKeyboardFocusHere(-1)