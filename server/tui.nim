import strformat, strutils, math, times
import illwill
import os

type
    View = enum
        BaseView
        AgentView
        ListenerView
        LogView
        LootView

    UserInterface = object
        tb: TerminalBuffer
        view: View
        x, y: tuple[start, center, ending: int]


#[
    Exit Application
]#
proc exitUi*() {.noconv.} =
    illwillDeinit()
    showCursor()
    quit(0)

proc renderListenerView(ui: var UserInterface) = 
    ui.tb.setForegroundColor(fgGreen, bright=false)
    ui.tb.drawRect(ui.x.start, 3, ui.tb.width-1, ui.tb.height-2)

proc renderAgentView(ui: var UserInterface) = 
    ui.tb.setForegroundColor(fgRed, bright=true)
    ui.tb.drawRect(ui.x.start, 3, ui.tb.width-1, ui.tb.height-2)


proc renderBaseView(ui: var UserInterface) = 
    ui.tb.setForegroundColor(fgWhite, bright=false)
    ui.tb.drawRect(ui.x.start, 3, ui.tb.width-1, ui.tb.height-2)

    ui.tb.setForegroundColor(fgCyan, bright=false)
    ui.tb.write(ui.x.start, 5, fmt"Width:    {ui.tb.width}")
    ui.tb.write(ui.x.start, 6, fmt"Center:  {ui.x.center}")
    ui.tb.write(ui.x.start, 7, fmt"Height: {ui.tb.height}")

#[
    Navigation Menu
    TODO: 
    ~ Refactor using foreach loop over sequence of navbar items
    ~ NavItem type: 
        text: string (pre- and append space automatically)
        view: View
        fgColor: ForegroundColor
        shortcut: Key
]#
proc renderNav(ui: var UserInterface) = 
    var offset: int = 0
    
    var baseNav = newBoxBuffer(ui.tb.width, ui.tb.height)
    baseNav.drawRect(ui.x.start, 0, ui.x.start + len(" Base ") + 1, 2, doubleStyle = (ui.view == BaseView))
    ui.tb.setForegroundColor(fgWhite, bright=true)
    ui.tb.write(baseNav)
    ui.tb.write(ui.x.start + 1, 1, " B", resetStyle, "ase ")

    offset += len(" Base ") + 2

    var listenerNav = newBoxBuffer(ui.tb.width, ui.tb.height)
    listenerNav.drawRect(ui.x.start + offset, 0, ui.x.start + len(" Listeners ") + offset + 1, 2, doubleStyle = (ui.view == ListenerView))
    ui.tb.setForegroundColor(fgGreen)
    ui.tb.write(listenerNav)
    ui.tb.write(ui.x.start + offset + 1, 1, " L", resetStyle, "isteners ")

    offset += len(" Listeners ") + 2

    var agentNav = newBoxBuffer(ui.tb.width, ui.tb.height)
    agentNav.drawRect(ui.x.start + offset, 0, ui.x.start+len(" Agents ") + offset + 1, 2, doubleStyle = (ui.view == AgentView))
    ui.tb.setForegroundColor(fgRed, bright=true)
    ui.tb.write(agentNav)
    ui.tb.write(ui.x.start + offset + 1, 1, " A", resetStyle, "gents ")

proc renderView(ui: var UserInterface) = 
    case ui.view:
    of ListenerView: ui.renderListenerView() 
    of AgentView: ui.renderAgentView() 
    else: ui.renderBaseView()

#[
    Initialize Terminal User Interface
]#

var input: string = "test"

proc initUi*() =
    
    var ui = UserInterface()

    illwillInit(fullscreen=true, mouse=false)
    setControlCHook(exitUi)
    hideCursor()
    
    while true:

        let 
            width =  terminalWidth()
            height = terminalHeight()

        # Horizontal positioning
        ui.x.start = 2
        ui.x.center = cast[int](math.round(width / 2).toInt) - 10
        ui.x.ending = width-1
        
        # Vertical positioning
        ui.y.start = 4
        ui.y.center = cast[int](math.round(height / 2).toInt) - 2
        ui.y.ending = height-1

        # Clear screen
        ui.tb = newTerminalBuffer(width, height)

        # Header
        let date: string = now().format("dd-MM-yyyy HH:mm:ss")
        ui.tb.write(ui.x.center, 0, "┏┏┓┏┓┏┓┓┏┏┓┏╋")
        ui.tb.write(ui.x.center, 1, "┗┗┛┛┗┗┫┗┻┗ ┛┗ 0.1")
        ui.tb.write(ui.x.center, 2, "      ┗  @virtualloc")   
        ui.tb.write(ui.x.ending - len(date), 1, date)

        # Navigation
        ui.renderNav()
        
        # Handle keyboard events
        var key: Key = getKey()
        case key 
        of Key.CtrlC: exitUi()
        of Key.CtrlL: 
            ui.view = ListenerView
        of Key.CtrlA:
            ui.view = AgentView
        of Key.CtrlB: 
            ui.view = BaseView
        else:
            #[
                TODO: 
                ~ Turn this into a textbox widget
            ]#
            if(ord(key) >= 32 and ord(key) < 127):
                input &= char(ord(key))
            if(ord(key) == 127 and len(input) >= 1): 
                input = input[0..len(input)-2]
            ui.tb.write(10, 10, input)

            discard

        ui.renderView()

        # Footer
        ui.tb.write(ui.x.start, ui.x.ending, "Close using [CTRL+C]")

        ui.tb.display()