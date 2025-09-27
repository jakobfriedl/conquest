import strformat, strutils, times
import imguin/[cimgui, glfw_opengl, simple]
import ../utils/[appImGui, colors]
import ../../common/types

type 
    EventlogComponent* = ref object of RootObj
        title: string 
        log*: ConsoleItems
        textSelect: ptr TextSelect
        showTimestamps: bool

proc getText(item: ConsoleItem): cstring = 
    if item.timestamp > 0: 
        let timestamp = item.timestamp.fromUnix().format("dd-MM-yyyy HH:mm:ss")
        return fmt"[{timestamp}]{$item.itemType}{item.text}".string 
    else: 
        return fmt"{$item.itemType}{item.text}".string 

proc getNumLines(data: pointer): csize_t {.cdecl.} =
    if data.isNil:
        return 0
    let log = cast[ConsoleItems](data)
    return log.items.len().csize_t

proc getLineAtIndex(i: csize_t, data: pointer, outLen: ptr csize_t): cstring {.cdecl.} =
    if data.isNil:
        return nil    
    let log = cast[ConsoleItems](data)
    let line = log.items[i].getText()
    if not outLen.isNil:
        outLen[] = line.len.csize_t
    return line

proc Eventlog*(title: string): EventlogComponent = 
    result = new EventlogComponent
    result.title = title
    result.log = new ConsoleItems
    result.log.items = @[]
    result.textSelect = textselect_create(getLineAtIndex, getNumLines, cast[pointer](result.log), 0)
    result.showTimestamps = false

#[
    API to add new log entry
]#
proc addItem*(component: EventlogComponent, itemType: LogType, data: string, timestamp: int64 = now().toTime().toUnix()) = 

    for line in data.split("\n"): 
        component.log.items.add(ConsoleItem(
            timestamp: timestamp,
            itemType: itemType,
            text: line
        ))

#[
    Drawing
]#
proc print(component: EventlogComponent, item: ConsoleItem) =     
    if (item.itemType != LOG_OUTPUT) and component.showTimestamps:
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

proc draw*(component: EventlogComponent, showComponent: ptr bool) = 
    igBegin(component.title, showComponent, 0)
    defer: igEnd() 

    try: 
        # Set styles of the eventlog window
        igPushStyleColor_Vec4(ImGui_Col_FrameBg.int32, vec4(0.1f, 0.1f, 0.1f, 1.0f))
        igPushStyleColor_Vec4(ImGui_Col_ScrollbarBg.int32, vec4(0.1f, 0.1f, 0.1f, 1.0f))
        igPushStyleColor_Vec4(ImGui_Col_Border.int32, vec4(0.2f, 0.2f, 0.2f, 1.0f))
        igPushStyleVar_Float(ImGui_StyleVar_FrameBorderSize .int32, 1.0f)

        let childWindowFlags = ImGuiChildFlags_NavFlattened.int32 or ImGui_ChildFlags_Borders.int32 or ImGui_ChildFlags_AlwaysUseWindowPadding.int32 or ImGuiChildFlags_FrameStyle.int32
        if igBeginChild_Str("##Log", vec2(-1.0f, -1.0f), childWindowFlags, ImGuiWindowFlags_HorizontalScrollbar.int32):            
            # Display eventlog items
            for item in component.log.items:
                component.print(item)
            
            # Right click context menu to toggle timestamps in eventlog
            if igBeginPopupContextWindow("EventlogSettings", ImGui_PopupFlags_MouseButtonRight.int32):
                if igCheckbox("Show timestamps", addr component.showTimestamps): 
                    igCloseCurrentPopup()
                igEndPopup()

            component.textSelect.textselect_update()
  
            # Auto-scroll to bottom
            if igGetScrollY() >= igGetScrollMaxY():
                igSetScrollHereY(1.0f)
                    
    except IndexDefect:
        # CTRL+A crashes when no items are in the eventlog
        discard
    
    finally: 
        igPopStyleColor(3)
        igPopStyleVar(1)
        igEndChild()
