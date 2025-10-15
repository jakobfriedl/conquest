import strutils, sequtils, algorithm, times
import imguin/[cimgui, glfw_opengl, simple]
import ../../utils/[appImGui, colors, utils]
import ../../../common/[types, utils]

type 
    TextareaWidget* = ref object of RootObj
        content: ConsoleItems
        contentDisplayed: ConsoleItems
        textSelect: ptr TextSelect
        showTimestamps: bool
        autoScroll: bool

# Text highlighting
proc getText(item: ConsoleItem): cstring = 
    if item.itemType != LOG_OUTPUT: 
        return "[" & item.timestamp & "]" & $item.itemType & item.text
    else: 
        return $item.itemType & item.text

proc getNumLines(data: pointer): csize_t {.cdecl.} =
    if data.isNil:
        return 0
    let content = cast[ConsoleItems](data)
    return content.items.len().csize_t

proc getLineAtIndex(i: csize_t, data: pointer, outLen: ptr csize_t): cstring {.cdecl.} =
    if data.isNil:
        return nil    
    let content = cast[ConsoleItems](data)
    let line = content.items[i].getText()
    if not outLen.isNil:
        outLen[] = line.len.csize_t
    return line

proc Textarea*(showTimestamps: bool = true, autoScroll: bool = true): TextareaWidget = 
    result = new TextareaWidget
    result.content = new ConsoleItems
    result.content.items = @[]
    result.contentDisplayed = new ConsoleItems
    result.contentDisplayed.items = @[]
    result.textSelect = textselect_create(getLineAtIndex, getNumLines, cast[pointer](result.contentDisplayed), 0)
    result.showTimestamps = showTimestamps
    result.autoScroll = autoScroll

# API to add new content entry
proc addItem*(component: TextareaWidget, itemType: LogType, data: string, timestamp: string = now().format("dd-MM-yyyy HH:mm:ss")) = 
    for line in data.split("\n"): 
        component.content.items.add(ConsoleItem(
            timestamp: timestamp,
            itemType: itemType,
            text: line
        ))

proc clear*(component: TextareaWidget) = 
    component.content.items.setLen(0)
    component.contentDisplayed.items.setLen(0)
    component.textSelect.textselect_clear_selection()

proc isEmpty*(component: TextareaWidget): bool = 
    return component.content.items.len() <= 0

# Drawing
proc print(component: TextareaWidget, item: ConsoleItem) =     
    if item.itemType != LOG_OUTPUT and component.showTimestamps:
        igTextColored(GRAY, "[" & item.timestamp & "]", nil)
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

proc draw*(component: TextareaWidget, size: ImVec2, filter: ptr ImGuiTextFilter = nil) = 
    try: 
        # Set styles of the eventlog window
        igPushStyleColor_Vec4(ImGui_Col_FrameBg.int32, vec4(0.1f, 0.1f, 0.1f, 1.0f))
        igPushStyleColor_Vec4(ImGui_Col_ScrollbarBg.int32, vec4(0.1f, 0.1f, 0.1f, 1.0f))
        igPushStyleColor_Vec4(ImGui_Col_Border.int32, vec4(0.2f, 0.2f, 0.2f, 1.0f))
        igPushStyleVar_Float(ImGui_StyleVar_FrameBorderSize .int32, 1.0f)

        let childWindowFlags = ImGuiChildFlags_NavFlattened.int32 or ImGui_ChildFlags_Borders.int32 or ImGui_ChildFlags_AlwaysUseWindowPadding.int32 or ImGuiChildFlags_FrameStyle.int32
        if igBeginChild_Str("##TextArea", size, childWindowFlags, ImGuiWindowFlags_HorizontalScrollbar.int32):            
            
            # Display items
            component.contentDisplayed.items.setLen(0)
            for item in component.content.items:

                # Handle search/filter
                if not filter.isNil():
                    if filter.ImGuiTextFilter_IsActive():
                        if not filter.ImGuiTextFilter_PassFilter(item.getText(), nil): 
                            continue 
                component.contentDisplayed.items.add(item)
                component.print(item)

            # Auto-scroll to bottom
            if component.autoScroll:
                if igGetScrollY() >= igGetScrollMaxY():
                    igSetScrollHereY(1.0f)
  
            component.textSelect.textselect_update()
                    
    except IndexDefect:
        # CTRL+A crashes when no items are in the text area
        discard
    
    finally: 
        igPopStyleColor(3)
        igPopStyleVar(1)
        igEndChild()