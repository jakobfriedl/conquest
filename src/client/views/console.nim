import strformat, strutils, sequtils, tables, times, algorithm, nimpy
import imguin/[cimgui, glfw_opengl, simple]
import ../utils/[appImGui, globals, utils]
import ../../types/[common, client]
import ../core/[task, websocket]
import ./widgets/textarea
export addItem

proc Console*(agentId: string): ConsoleComponent =
    result = new ConsoleComponent
    result.agentId = agentId
    result.showConsole = false
    zeroMem(addr result.inputBuffer[0], MAX_INPUT_LENGTH)
    result.textarea = Textarea()
    result.history = @[]
    result.historyPosition = -1
    result.currentInput = ""

    # Search functionality
    result.searchActive = false
    zeroMem(addr result.searchBuffer[0], 256)
    result.searchMatches = @[]
    result.currentMatch = -1
    result.scrollToCurrentMatch = false

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
        # Handle Tab-autocompletion for agent commands
        let commands = cq.scriptManager.getCommands().keys().toSeq() & @["help "]

        # Get the word to complete
        let inputEndPos = data.CursorPos
        var inputStartPos = inputEndPos

        while inputStartPos > 0:
            let c = cast[ptr UncheckedArray[char]](data.Buf)[inputStartPos - 1]
            if c in [' ', '\t', ',', ';']:
                break
            dec inputStartPos
        
        let inputLen = inputEndPos - inputStartPos
        var currentWord = newString(inputLen)
        for i in 0..<inputLen:
            currentWord[i] = cast[ptr UncheckedArray[char]](data.Buf)[inputStartPos + i]
        
        # Check for matches
        var matches: seq[string] = @[]
        for cmd in commands: 
            if cmd.toLowerAscii().startsWith(currentWord.toLowerAscii()): 
                matches.add(cmd)

        # No matching commands found
        if matches.len() == 0: 
            return 0
        
        elif matches.len() == 1:
            data.ImGuiInputTextCallbackData_DeleteChars(inputStartPos.cint, inputLen.cint)
            data.ImGuiInputTextCallbackData_InsertChars(data.CursorPos, matches[0].cstring, nil)
        
        # More than 1 matching command -> complete common prefix
        else:
            var prefixLen = inputLen 

            while prefixLen < matches[0].len(): 
                let c = matches[0][prefixLen]
                var allMatch = true
                
                for i in 1 ..< matches.len(): 
                    if prefixLen >= matches[i].len() or matches[i][prefixLen] != c: 
                        allMatch = false
                        break

                if not allMatch:
                    break

                inc prefixLen
        
            if prefixLen > inputLen:
                data.ImGuiInputTextCallbackData_DeleteChars(inputStartPos.cint, inputLen.cint)
                data.ImGuiInputTextCallbackData_InsertChars(data.CursorPos, matches[0][0..<prefixLen].cstring, nil)

            return 0

    else: discard

#[
    Handling console commands
]#
proc displayHelp(component: ConsoleComponent) =
   for group, commands in cq.scriptManager.groups:
        component.textarea.addItem(LOG_OUTPUT, group.toUpperAscii())
        for cmd in commands.values():
            component.textarea.addItem(LOG_OUTPUT, " * " & cmd.name.alignLeft(25) & cmd.description)
        component.textarea.addItem(LOG_OUTPUT, "")

proc displayCommandHelp(component: ConsoleComponent, command: Command) =
    var usage = command.name & " " & command.arguments.mapIt(
        if it.isFlag and it.argType == BOOL:
            "[" & it.flag & "]"
        elif it.isFlag:
            "[" & it.flag & " " & it.name & "]"
        elif it.isRequired:
            "<" & it.name & ">"
        else:
            "[" & it.name & "]"
    ).join(" ")
    
    component.textarea.addItem(LOG_OUTPUT, command.description)
    if command.mitre.len() > 0: 
        component.textarea.addItem(LOG_OUTPUT, "MITRE ATT&CK: " & command.mitre.join(", "))
    component.textarea.addItem(LOG_OUTPUT, "")
    component.textarea.addItem(LOG_OUTPUT, "Usage: " & usage)
    component.textarea.addItem(LOG_OUTPUT, "Example: " & command.example)
    component.textarea.addItem(LOG_OUTPUT, "")
    
    var positionalArgs: seq[Argument] = @[]
    var optionalArgs: seq[Argument] = @[]
    
    for arg in command.arguments:
        if arg.isRequired and not arg.isFlag:
            positionalArgs.add(arg)
        else:
            optionalArgs.add(arg)
    
    # Display positional arguments
    let widths: seq[int] = @[25, 10] 

    if positionalArgs.len > 0:
        component.textarea.addItem(LOG_OUTPUT, "Required arguments:")
        
        for arg in positionalArgs:
            let argName = arg.name.alignLeft(widths[0])
            let argType = ($arg.argType).toUpperAscii().alignLeft(widths[1])
            
            # Display multi-line argument description with proper alignment
            let descLines = arg.description.split('\n')
            component.textarea.addItem(LOG_OUTPUT, "  " & argName & " " & argType & " " & descLines[0])
            for i in 1..<descLines.len:
                component.textarea.addItem(LOG_OUTPUT, "  " & ' '.repeat(widths[0]) & " " & ' '.repeat(widths[1]) & " " & descLines[i])
        
        component.textarea.addItem(LOG_OUTPUT, "")
    
    # Display optional arguments
    if optionalArgs.len > 0:
        component.textarea.addItem(LOG_OUTPUT, "Optional arguments:")
        
        for arg in optionalArgs:
            let argName = if arg.isFlag and arg.argType == BOOL:
                arg.flag.alignLeft(widths[0])
            elif arg.isFlag:
                (arg.flag & " " & arg.name).alignLeft(widths[0])
            else:
                arg.name.alignLeft(widths[0])
            
            let argType = ($arg.argType).toUpperAscii().alignLeft(widths[1])
            
            # Display multi-line argument description with proper alignment
            let descLines = arg.description.split('\n')
            component.textarea.addItem(LOG_OUTPUT, "  " & argName & " " & argType & " " & descLines[0])
            for i in 1..<descLines.len:
                component.textarea.addItem(LOG_OUTPUT, "  " & ' '.repeat(widths[0]) & " " & ' '.repeat(widths[1]) & " " & descLines[i])

proc handleHelp(component: ConsoleComponent, parsed: seq[string]) =
    try:
        # Try parsing the first argument passed to 'help' as a command
        component.displayCommandHelp(cq.scriptManager.getCommand(parsed[1].toLowerAscii()))
    except IndexDefect:
        # 'help' command is called without additional parameters -> show all available commands
        component.displayHelp()
    except ValueError:
        # Command was not found
        component.textarea.addItem(LOG_ERROR, "The command '" & parsed[1] & "' does not exist.")

    # Add newline at the end of help text
    component.textarea.addItem(LOG_OUTPUT, "")

proc handleAgentCommand*(component: ConsoleComponent, input: string) =
    # Insert newline before new command
    component.textarea.addItem(LOG_OUTPUT, "")

    # Convert user input into sequence of string arguments
    let parsedArgs = parseInput(input)

    # Handle 'help' command
    if parsedArgs[0].toLowerAscii() == "help":
        component.textarea.addItem(LOG_COMMAND, input)
        component.handleHelp(parsedArgs)
        return
        
    # Handle commands with actions on the agent
    try:
        let command = cq.scriptManager.getCommand(parsedArgs[0].toLowerAscii())
        
        # If the command has a handler, execute it with the parsed arguments
        if command.hasHandler:
            let args = command.parseArguments(parsedArgs[1..^1])        
            discard command.handler.callObject(cq.sessions.agents[component.agentId].agentId, input, args)
        else:
            sendTask(cq.sessions.agents[component.agentId].agentId, input)

    except Exception:
        cq.connection.sendLog(component.agentId, component.textarea.addItem(LOG_COMMAND, input))
        cq.connection.sendLog(component.agentId, component.textarea.addItem(LOG_ERROR, getCurrentExceptionMsg()))

proc listProcesses*(component: ConsoleComponent, rootProcesses: seq[uint32], processTable: OrderedTable[uint32, ProcessInfo]) = 
    var output = ""
    
    output.add(component.textarea.addItem(LOG_INFO, "Output: "))
    
    # Header row
    let headers = @["PID", "PPID", "Process name", "Session", "User context"]
    output.add(component.textarea.addItem(LOG_OUTPUT, headers[0].alignLeft(10) & headers[1].alignLeft(10) & headers[2].alignLeft(80) & headers[3].alignLeft(10) & headers[4]))
    output.add(component.textarea.addItem(LOG_OUTPUT, "-".repeat(len(headers[0])).alignLeft(10) & "-".repeat(len(headers[1])).alignLeft(10) & "-".repeat(len(headers[2])).alignLeft(80) & "-".repeat(len(headers[3])).alignLeft(10) & "-".repeat(len(headers[4]))))
    
    # Format and print process
    proc printProcess(pid: uint32, indentSpaces: int = 0) =
        if not processTable.contains(pid) or pid == 0: 
            return
        
        var process = processTable[pid]
        let processName = " ".repeat(indentSpaces) & process.name
        let line = ($process.pid).alignLeft(10) & ($process.ppid).alignLeft(10) & processName.alignLeft(80) & ($process.session).alignLeft(10) & process.user                        
        output.add(component.textarea.addItem(LOG_OUTPUT, line, highlight = int(pid) == cq.sessions.agents[component.agentId].pid))
        
        # Recursively print child processes with indentation
        for childPid in process.children.sorted():
            printProcess(childPid, indentSpaces + 2)
    
    for pid in rootProcesses: 
        printProcess(pid)
    
    # Send formatted output to team server for logging
    cq.connection.sendLog(component.agentId, output)

proc listDirectoryContents*(component: ConsoleComponent, path: string, entries: seq[DirectoryEntry]) = 
    var 
        totalFiles = 0
        totalDirs = 0
        output = ""
    
    output.add(component.textarea.addItem(LOG_INFO, "Output: "))
    output.add(component.textarea.addItem(LOG_OUTPUT, "Directory: " & path))
    output.add(component.textarea.addItem(LOG_OUTPUT, ""))
    
    # Table Headers
    let headers = @["Flags", "Last modified", "Size", "Name"]    
    output.add(component.textarea.addItem(LOG_OUTPUT, headers[0].alignLeft(8) & headers[1].alignLeft(25) & headers[2].alignLeft(15) & headers[3]))
    output.add(component.textarea.addItem(LOG_OUTPUT,  "-".repeat(headers[0].len).alignLeft(8) & "-".repeat(headers[1].len).alignLeft(25) & "-".repeat(headers[2].len).alignLeft(15) & "-".repeat(headers[3].len)))
    
    # Process entries
    for entry in entries:
        var mode = ""
        mode &= (if (entry.flags and cast[uint8](IS_DIR)) != 0: (inc totalDirs; "d") else: (inc totalFiles; "-"))
        mode &= (if (entry.flags and cast[uint8](IS_ARCHIVE)) != 0: "a" else: "-")
        mode &= (if (entry.flags and cast[uint8](IS_READONLY)) != 0: "r" else: "-")
        mode &= (if (entry.flags and cast[uint8](IS_HIDDEN)) != 0: "h" else: "-")
        mode &= (if (entry.flags and cast[uint8](IS_SYSTEM)) != 0: "s" else: "-")
        
        # Date formatting
        let dt = fromUnix(entry.lastWriteTime)
        let dateTimeStr = dt.format("dd/MM/yyyy HH:mm:ss")
        
        # Size formatting
        let sizeStr = if (entry.flags and cast[uint8](IS_DIR)) != 0: "<DIR>" else: $entry.size
        
        # Build the entry line using consistent alignment
        output.add(component.textarea.addItem(LOG_OUTPUT, mode.alignLeft(8) & dateTimeStr.alignLeft(25) & sizeStr.alignLeft(15) & entry.name))
    
    output.add(component.textarea.addItem(LOG_OUTPUT, ""))
    output.add(component.textarea.addItem(LOG_OUTPUT, $totalFiles & " file(s)"))
    output.add(component.textarea.addItem(LOG_OUTPUT, $totalDirs & " dir(s)"))
    
    # Send formatted output to team server for logging
    cq.connection.sendLog(component.agentId, output)

proc draw*(component: ConsoleComponent) =
    if not cq.sessions.agents.hasKey(component.agentId): return

    let agent = cq.sessions.agents[component.agentId]

    igBegin(agent.consoleTitle.cstring, addr component.showConsole, 0)
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
    ]#
    let consolePadding: float = 10.0f 
    let footerHeight = (consolePadding * 2) + (igGetStyle().ItemSpacing.y + igGetFrameHeightWithSpacing()) * 0.75f
    let textSpacing = igGetStyle().ItemSpacing.x        

    #[
        Session information 
    ]#
    igAlignTextToFramePadding()
    let domain = if agent.domain.isEmptyOrWhitespace(): "" else: fmt".{agent.domain}"
    let sessionInfo = fmt"{agent.username}@{agent.hostname}{domain} | {agent.ipInternal} | {$agent.pid}/{agent.process}".cstring
    igTextColored(GRAY, sessionInfo)
    igSameLine(0.0f, 0.0f)

    #[
        Search bar 
    ]#
    
    # Handle CTRL+F
    if igIsWindowFocused(ImGui_FocusedFlags_ChildWindows.int32) and io.KeyCtrl and igIsKeyPressed_Bool(ImGuiKey_F, false):
        component.searchActive = true
        component.searchFocus = true

    let searchBoxWidth: float32 = 300.0f
    let buttonWidth: float32 = 25.0f

    let matchCount = component.searchMatches.len()
    let matchLabel = 
        if ($cast[cstring](addr component.searchBuffer[0])).strip().len() == 0: ""
        elif matchCount == 0: "No results"
        elif component.currentMatch >= 0: fmt"{component.currentMatch + 1} / {matchCount}"
        else: fmt"0 / {matchCount}"
    
    let totalWidth =
        if component.searchActive: igCalcTextSize(matchLabel.cstring, nil, false, 0.0f).x + textSpacing + searchBoxWidth + 5 * buttonWidth + 5 * textSpacing
        else: 0.0f

    let availableSize = igGetContentRegionAvail()

    # When search is inactive, show a button to open the search bar 
    if not component.searchActive:
        let searchBtnWidth = igCalcTextSize((ICON_FA_MAGNIFYING_GLASS & " Search").cstring, nil, false, 0.0f).x + igGetStyle().FramePadding.x * 2.0f
        igSameLine(0.0f, max(0.0f, availableSize.x - searchBtnWidth))
        igAlignTextToFramePadding()
        if igButton((ICON_FA_MAGNIFYING_GLASS & " Search").cstring, vec2(0.0f, 0.0f)): 
            component.searchActive = true
            component.searchFocus = true

        if igIsItemHovered(ImGuiHoveredFlags_None.int32):
            igBeginTooltip()
            igText("Press CTRL+F to search console.")
            igEndTooltip()

    # When search is active, show the search bar right-aligned or in a new line if it doesn't fit next to the session information
    else:
        if not component.searchActive or (availableSize.x >= totalWidth):
            igSameLine(0.0f, max(0.0f, availableSize.x - totalWidth))
        else:
            igNewLine()

        igAlignTextToFramePadding()
        igTextColored(GRAY, matchLabel.cstring)
        igSameLine(0.0f, textSpacing)

        # Focus search bar
        if component.searchFocus:
            igSetKeyboardFocusHere(0)
            component.searchFocus = false

        igAlignTextToFramePadding()
        igSetNextItemWidth(searchBoxWidth)
        igInputTextWithHint("##ConsoleSearch", ICON_FA_MAGNIFYING_GLASS.cstring, cast[cstring](addr component.searchBuffer[0]), 256, 0, nil, nil)
        let searchInputFocused = igIsItemFocused()
        if igIsItemHovered(ImGuiHoveredFlags_None.int32):
            igBeginTooltip()
            igText("[Alt + C]           Match case.")
            igText("[Alt + R]           Use regular expression.")
            igText("[Enter]             Jump to next match.")
            igText("[Shift + Enter]     Jump to previous match.")
            igText("[Escape]            Close console search.")
            igEndTooltip()

        # Toggle case matching
        igSameLine(0.0f, textSpacing)
        let matchCase = component.searchMatchCase
        if matchCase:
            igPushStyleColor_Vec4(ImGui_Col_Button.int32, igGetStyle().Colors[ImGui_Col_ButtonActive.int32])
        
        if igButton("Aa".cstring, vec2(buttonWidth, 0.0f)):
            component.searchMatchCase = not component.searchMatchCase
            component.searchPrevQuery = ""
            component.searchFocus = true
        
        if matchCase:
            igPopStyleColor(1)

        # Toggle regular expression support
        igSameLine(0.0f, textSpacing)
        let regexActive = component.searchRegex
        if regexActive:
            igPushStyleColor_Vec4(ImGui_Col_Button.int32, igGetStyle().Colors[ImGui_Col_ButtonActive.int32])
        
        if igButton(".*".cstring, vec2(buttonWidth, 0.0f)):
            component.searchRegex = not component.searchRegex
            component.searchPrevQuery = ""
            component.searchFocus = true
        
        if regexActive:
            igPopStyleColor(1)

        # Match navigation
        igSameLine(0.0f, textSpacing)
        if igButton(ICON_FA_ARROW_UP, vec2(buttonWidth, 0.0f)):
            if matchCount > 0:
                component.currentMatch = (component.currentMatch - 1 + matchCount) mod matchCount   # Rotate to next match
                component.scrollToCurrentMatch = true
                component.textarea.autoScroll = false

        igSameLine(0.0f, textSpacing)
        if igButton(ICON_FA_ARROW_DOWN, vec2(buttonWidth, 0.0f)):
            if matchCount > 0:
                component.currentMatch = (component.currentMatch + 1) mod matchCount    # Rotate to previous match
                component.scrollToCurrentMatch = true
                component.textarea.autoScroll = false

        # Close and reset console search
        igSameLine(0.0f, textSpacing)
        if igButton(ICON_FA_XMARK, vec2(buttonWidth, 0.0f)):
            component.searchActive = false
            zeroMem(addr component.searchBuffer[0], 256)
            component.searchPrevQuery = ""
            component.searchMatches = @[]
            component.currentMatch = -1
            component.scrollToCurrentMatch = false
            component.textarea.autoScroll = true
            focusInput = true

        # Compute the matches as soon as the query changes
        let currentQuery = ($cast[cstring](addr component.searchBuffer[0])).strip()
        if currentQuery != component.searchPrevQuery:
            component.searchPrevQuery = currentQuery
            component.searchMatches = component.textarea.search(currentQuery, component.searchMatchCase, component.searchRegex)
            
            # Jump to first match
            if component.searchMatches.len > 0:
                component.currentMatch = 0
                component.scrollToCurrentMatch = true
            
            else:
                component.currentMatch = -1

        # Handle keyboard shortcuts:
        # - Alt+C to toggle case-sensitivity
        # - Alt+R to toggle regex mode
        # - Enter to jump to next match
        # - Shift+Enter to jump to previous match
        # - Escape to close console search
        
        if searchInputFocused and io.KeyAlt:
            if igIsKeyPressed_Bool(ImGuiKey_C, false):
                component.searchMatchCase = not component.searchMatchCase
                component.searchPrevQuery = ""
                
            elif igIsKeyPressed_Bool(ImGuiKey_R, false):
                component.searchRegex = not component.searchRegex
                component.searchPrevQuery = ""

        if searchInputFocused and igIsKeyPressed_Bool(ImGuiKey_Enter, false):
            if matchCount > 0:
                if io.KeyShift:
                    component.currentMatch = (component.currentMatch - 1 + matchCount) mod matchCount
                else:
                    component.currentMatch = (component.currentMatch + 1) mod matchCount
                component.scrollToCurrentMatch = true
                component.textarea.autoScroll = false

        if searchInputFocused and igIsKeyPressed_Bool(ImGuiKey_Escape, false):
            component.searchActive = false
            zeroMem(addr component.searchBuffer[0], 256)
            component.searchPrevQuery = ""
            component.searchMatches = @[]
            component.currentMatch = -1
            component.scrollToCurrentMatch = false
            component.textarea.autoScroll = true
            focusInput = true

    #[
        Console textarea
    ]#
    component.textarea.draw(
        vec2(-1.0f, -footerHeight),
        component.searchMatches,
        component.currentMatch,
        addr component.scrollToCurrentMatch
    )
    
    # Padding 
    igDummy(vec2(0.0f, consolePadding))
    
    #[
        Input field with prompt indicator
    ]#
    igText(fmt"[{agent.agentId}]".cstring) 
    igSameLine(0.0f, textSpacing)
    
    # Calculate available width for input
    igSetNextItemWidth(igGetContentRegionAvail().x)
    
    let inputFlags = ImGuiInputTextFlags_EnterReturnsTrue.int32 or ImGuiInputTextFlags_EscapeClearsAll.int32 or ImGuiInputTextFlags_CallbackHistory.int32 or ImGuiInputTextFlags_CallbackCompletion.int32
    if igInputText("##Input", cast[cstring](addr component.inputBuffer[0]), MAX_INPUT_LENGTH, inputFlags, callback, cast[pointer](component)):

        let command = ($cast[cstring]((addr component.inputBuffer[0]))).strip()
        if not command.isEmptyOrWhitespace(): 
            # Send command to team server
            component.handleAgentCommand(command)

            # Add command to console history
            component.history.add(command)
            component.historyPosition = -1 

        zeroMem(addr component.inputBuffer[0], MAX_INPUT_LENGTH)
        focusInput = true
    
    igSetItemDefaultFocus()
    if focusInput: 
        igSetKeyboardFocusHere(-1)