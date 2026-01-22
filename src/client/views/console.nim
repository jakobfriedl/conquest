import strformat, strutils, sequtils, tables, times, algorithm, nimpy, std/paths
import imguin/[cimgui, glfw_opengl, simple]
import ../utils/[appImGui, globals]
import ../../common/[types, utils]
import ../core/[task, websocket, context]
import ./widgets/textarea
import ./moduleManager
export addItem

# const MAX_INPUT_LENGTH = 4096 # Input needs to allow enough characters for long commands (e.g. Rubeus tickets)
# type 
#     ConsoleComponent* = ref object of RootObj
#         agent*: UIAgent
#         showConsole*: bool
#         inputBuffer: array[MAX_INPUT_LENGTH, char]
#         console*: TextareaWidget
#         history: seq[string]
#         historyPosition: int 
#         currentInput: string
#         filter: ptr ImGuiTextFilter

proc Console*(agent: UIAgent): ConsoleComponent =
    result = new ConsoleComponent
    result.agent = agent
    result.showConsole = true
    zeroMem(addr result.inputBuffer[0], MAX_INPUT_LENGTH)
    result.console = Textarea()
    result.history = @[]
    result.historyPosition = -1  
    result.currentInput = ""
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
        # Handle Tab-autocompletion for agent commands
        let commands = cq.moduleManager.getCommands(component.agent.modules).mapIt(it.name & " ") & @["help "]

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
   for group, commands in cq.moduleManager.getCommandGroups(component.agent.modules):
        component.console.addItem(LOG_OUTPUT, group.toUpperAscii())
        for cmd in commands.sorted():
            component.console.addItem(LOG_OUTPUT, " * " & cmd.name.alignLeft(25) & cmd.description)
        component.console.addItem(LOG_OUTPUT, "")

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
    
    component.console.addItem(LOG_OUTPUT, command.description)
    component.console.addItem(LOG_OUTPUT, "")
    component.console.addItem(LOG_OUTPUT, "Usage: " & usage)
    component.console.addItem(LOG_OUTPUT, "Example: " & command.example)
    component.console.addItem(LOG_OUTPUT, "")
    
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
        component.console.addItem(LOG_OUTPUT, "Required arguments:")
        
        for arg in positionalArgs:
            let argName = arg.name.alignLeft(widths[0])
            let argType = ($arg.argType).toUpperAscii().alignLeft(widths[1])
            
            # Display multi-line argument description with proper alignment
            let descLines = arg.description.split('\n')
            component.console.addItem(LOG_OUTPUT, "  " & argName & " " & argType & " " & descLines[0])
            for i in 1..<descLines.len:
                component.console.addItem(LOG_OUTPUT, "  " & ' '.repeat(30) & " " & ' '.repeat(10) & " " & descLines[i])
        
        component.console.addItem(LOG_OUTPUT, "")
    
    # Display optional arguments
    if optionalArgs.len > 0:
        component.console.addItem(LOG_OUTPUT, "Optional arguments:")
        
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
            component.console.addItem(LOG_OUTPUT, "  " & argName & " " & argType & " " & descLines[0])
            for i in 1..<descLines.len:
                component.console.addItem(LOG_OUTPUT, "  " & ' '.repeat(widths[0]) & " " & ' '.repeat(widths[1]) & " " & descLines[i])

proc handleHelp(component: ConsoleComponent, parsed: seq[string]) =
    try:
        # Try parsing the first argument passed to 'help' as a command
        component.displayCommandHelp(cq.moduleManager.getCommand(parsed[1]))
    except IndexDefect:
        # 'help' command is called without additional parameters -> show all available commands
        component.displayHelp()
    except ValueError:
        # Command was not found
        component.console.addItem(LOG_ERROR, "The command '" & parsed[1] & "' does not exist.")

    # Add newline at the end of help text
    component.console.addItem(LOG_OUTPUT, "")

proc handleAgentCommand*(component: ConsoleComponent, input: string) =
    # Add command to console
    component.console.addItem(LOG_COMMAND, input)

    # Convert user input into sequence of string arguments
    let parsedArgs = parseInput(input)

    # Handle 'help' command
    if parsedArgs[0] == "help":
        component.handleHelp(parsedArgs)
        return
        
    # Handle commands with actions on the agent
    try:
        let command = cq.moduleManager.getCommand(parsedArgs[0])
        
        # If the command has a handler, execute it with the parsed arguments
        if command.hasHandler:
            let args = command.parseArguments(parsedArgs[1..^1])        
            discard command.handler.callObject(component.agent.agentId, input, args)
        else:
            sendTask(component.agent.agentId, input)

    except CatchableError:
        component.console.addItem(LOG_ERROR, getCurrentExceptionMsg())

proc listProcesses*(component: ConsoleComponent, rootProcesses: seq[uint32], processTable: OrderedTable[uint32, ProcessInfo]) = 
    # Header row
    let headers = @["PID", "PPID", "Process name", "Session", "User context"]
    component.console.addItem(LOG_OUTPUT, headers[0].alignLeft(10) & headers[1].alignLeft(10) & headers[2].alignLeft(80) & headers[3].alignLeft(10) & headers[4])
    component.console.addItem(LOG_OUTPUT, "-".repeat(len(headers[0])).alignLeft(10) & "-".repeat(len(headers[1])).alignLeft(10) & "-".repeat(len(headers[2])).alignLeft(80) & "-".repeat(len(headers[3])).alignLeft(10) & "-".repeat(len(headers[4])))

    # Format and print process
    proc printProcess(pid: uint32, indentSpaces: int = 0) =
        if not processTable.contains(pid) or pid == 0: 
            return
        
        var process = processTable[pid]
        let processName = " ".repeat(indentSpaces) & process.name
        let line = ($process.pid).alignLeft(10) & ($process.ppid).alignLeft(10) & processName.alignLeft(80) & ($process.session).alignLeft(10) & process.user                        
        component.console.addItem(LOG_OUTPUT, line, "", int(pid) == component.agent.pid)

        # Recursively print child processes with indentation
        for childPid in process.children.sorted():
            printProcess(childPid, indentSpaces + 2)

    for pid in rootProcesses: 
        printProcess(pid)

proc listDirectoryContents*(component: ConsoleComponent, path: string, entries: seq[DirectoryEntry]) = 
    var 
        totalFiles = 0
        totalDirs = 0
    
    # Path Header
    component.console.addItem(LOG_OUTPUT, "Directory: " & path)
    component.console.addItem(LOG_OUTPUT, "")

    # Table Headers
    let headers = @["Mode", "LastWriteTime", "Length", "Name"]
    let headerLine = headers[0].alignLeft(8) & headers[1].alignLeft(25) & headers[2].alignLeft(15) & headers[3]
    let separator = "-".repeat(headers[0].len).alignLeft(8) & "-".repeat(headers[1].len).alignLeft(25) & "-".repeat(headers[2].len).alignLeft(15) & "-".repeat(headers[3].len)
    
    component.console.addItem(LOG_OUTPUT, headerLine)
    component.console.addItem(LOG_OUTPUT, separator)
    
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
        component.console.addItem(LOG_OUTPUT, mode.alignLeft(8) & dateTimeStr.alignLeft(25) & sizeStr.alignLeft(15) & $lastPathPart(cast[Path](entry.path))) # Only display the last part of the path
    
    # Summary footer
    component.console.addItem(LOG_OUTPUT, "")
    component.console.addItem(LOG_OUTPUT, $totalFiles & " file(s)")
    component.console.addItem(LOG_OUTPUT, $totalDirs & " dir(s)")


proc draw*(component: ConsoleComponent) =
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
    
    let searchBoxWidth: float32 = 400.0f
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

    #[
        Console textarea
    ]# 
    component.console.draw(vec2(-1.0f, -footerHeight), component.filter)
    
    # Padding 
    igDummy(vec2(0.0f, consolePadding))
    
    #[
        Input field with prompt indicator
    ]#
    igText(fmt"[{component.agent.agentId}]".cstring) 
    igSameLine(0.0f, textSpacing)
    
    # Calculate available width for input
    igGetContentRegionAvail(addr availableSize)
    igSetNextItemWidth(availableSize.x)
    
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