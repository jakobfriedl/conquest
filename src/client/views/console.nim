import strformat, strutils, sequtils
import imguin/[cimgui, glfw_opengl, simple]
import ../utils/[appImGui, colors]
import ../../common/[types, utils]
import ../../modules/manager
import ../core/[task, websocket]
import ./widgets/textarea
export addItem

const MAX_INPUT_LENGTH = 4096 # Input needs to allow enough characters for long commands (e.g. Rubeus tickets)
type 
    ConsoleComponent* = ref object of RootObj
        agent*: UIAgent
        showConsole*: bool
        inputBuffer: array[MAX_INPUT_LENGTH, char]
        console*: TextareaWidget
        history: seq[string]
        historyPosition: int 
        currentInput: string
        filter: ptr ImGuiTextFilter

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
        let commands = getCommands(component.agent.modules).mapIt(it.name & " ") & @["help "]

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
    for cmd in getCommands(component.agent.modules):
        component.console.addItem(LOG_OUTPUT, " * " & cmd.name.alignLeft(25) & cmd.description)

proc displayCommandHelp(component: ConsoleComponent, command: Command) =
    var usage = command.name & " " & command.arguments.mapIt(
        if it.isRequired: "<" & it.name & ">" else: "[" & it.name & "]"
    ).join(" ")
    
    component.console.addItem(LOG_OUTPUT, command.description)
    component.console.addItem(LOG_OUTPUT, "Usage    : " & usage)    
    component.console.addItem(LOG_OUTPUT, "Example  : " & command.example)
    component.console.addItem(LOG_OUTPUT, "")

    if command.arguments.len > 0:
        component.console.addItem(LOG_OUTPUT, "Arguments:")
        
        let header = @["Name", "Type", "Required", "Description"]
        component.console.addItem(LOG_OUTPUT, "   " & header[0].alignLeft(15) & " " & header[1].alignLeft(6) & " " & header[2].alignLeft(8) & " " & header[3])
        component.console.addItem(LOG_OUTPUT, "   " & '-'.repeat(15) & " " & '-'.repeat(6) & " " & '-'.repeat(8) & " " & '-'.repeat(20))
        
        for arg in command.arguments:
            let isRequired = if arg.isRequired: "YES" else: "NO"
            component.console.addItem(LOG_OUTPUT, " * " & arg.name.alignLeft(15) & " " & ($arg.argumentType).toUpperAscii().alignLeft(6) & " " & isRequired.align(8) & " " & arg.description)

proc handleHelp(component: ConsoleComponent, parsed: seq[string]) =
    try:
        # Try parsing the first argument passed to 'help' as a command
        component.displayCommandHelp(getCommandByName(parsed[1]))
    except IndexDefect:
        # 'help' command is called without additional parameters
        component.displayHelp()
    except ValueError:
        # Command was not found
        component.console.addItem(LOG_ERROR, "The command '" & parsed[1] & "' does not exist.")

    # Add newline at the end of help text
    component.console.addItem(LOG_OUTPUT, "")

proc handleAgentCommand*(component: ConsoleComponent, connection: WsConnection, input: string) =
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
        let 
            command = getCommandByName(parsedArgs[0])
            task = createTask(component.agent.agentId, component.agent.listenerId, command, parsedArgs[1..^1])

        connection.sendAgentTask(component.agent.agentId, input, task)
        component.console.addItem(LOG_INFO, "Tasked agent to " & command.description.toLowerAscii() & " (" & Uuid.toString(task.taskId) & ")")

    except CatchableError:
        component.console.addItem(LOG_ERROR, getCurrentExceptionMsg())

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
            component.handleAgentCommand(connection, command)

            # Add command to console history
            component.history.add(command)
            component.historyPosition = -1 

        zeroMem(addr component.inputBuffer[0], MAX_INPUT_LENGTH)
        focusInput = true
    
    igSetItemDefaultFocus()
    if focusInput: 
        igSetKeyboardFocusHere(-1)