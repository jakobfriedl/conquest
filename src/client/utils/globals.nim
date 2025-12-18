import ./fonticon/IconsFontAwesome6
import ./utils

const CONQUEST_ROOT* {.strdefine.} = ""

const WIDGET_SESSIONS* =  " " & ICON_FA_LIST & " " & "Sessions [Table View]"
const WIDGET_LISTENERS* = " " & ICON_FA_SATELLITE_DISH & " " & "Listeners"
const WIDGET_EVENTLOG* = " " & ICON_FA_CLIPBOARD_LIST & " " & "Eventlog"
const WIDGET_DOWNLOADS* = " " & ICON_FA_DOWNLOAD & " " & "Downloads"
const WIDGET_SCREENSHOTS* = " " & ICON_FA_IMAGE & " " & "Screenshots"
const WIDGET_PROCESS_BROWSER* = " " & ICON_FA_MICROCHIP & " " & "Process Browser"

const GRAY* = vec4(0.369f, 0.369f, 0.369f, 1.0f)
const CONSOLE_ERROR* = vec4(0.878f, 0.188f, 0.149f, 1.0f)
const CONSOLE_INFO* = vec4(0.588f, 0.843f, 0.89f, 1.0f)
const CONSOLE_SUCCESS* = vec4(0.176f, 0.569f, 0.075f, 1.0f)
const CONSOLE_WARNING* = vec4(1.0f, 0.5f, 0.0f, 1.0f)
const CONSOLE_COMMAND* = vec4(0.922f, 0.914f, 0.463f, 1.0f)
const CONSOLE_HIGHLIGHT* = vec4(0.890f, 0.855f, 0.161f, 1.0f)