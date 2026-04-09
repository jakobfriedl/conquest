import strutils, times, tables, regex
import imguin/[cimgui, glfw_opengl]
import ../../utils/[appImGui, globals]
import ../../../types/[common, client]

# Text highlighting
proc getText*(item: ConsoleItem): cstring =
    case item.itemType
    of LOG_OUTPUT:
        return ($item.itemType & item.text).cstring
    else:
        return ("[" & item.timestamp & "]" & $item.itemType & item.text).cstring

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
    result.textSelect = textselect_create(getLineAtIndex, getNumLines, cast[pointer](result.content), 0)
    result.showTimestamps = showTimestamps
    result.autoScroll = autoScroll

# API to add new content entry
proc addItem*(component: TextareaWidget, itemType: LogType, data: string, timestamp: string = now().format("dd-MM-yyyy HH:mm:ss"), highlight: bool = false): string {.discardable.} =
    result = ""
    for line in data.split("\n"):
        let item = ConsoleItem(
            timestamp: timestamp,
            itemType: itemType,
            text: line,
            highlight: highlight
        )
        component.content.items.add(item)
        result &= $(item.getText()) & "\n"

proc addItem*(component: TextareaWidget, item: ConsoleItem): string {.discardable.} =
    component.content.items.add(item)
    result = $(item.getText())

proc clear*(component: TextareaWidget) =
    component.content.items.setLen(0)
    component.textSelect.textselect_clear_selection()

proc isEmpty*(component: TextareaWidget): bool =
    return component.content.items.len() <= 0

# Returns a list of all matched words across all lines.
proc search*(component: TextareaWidget, query: string, matchCase, useRegex: bool = false): seq[tuple[line: int, a: int, b: int]] =
    if query.len == 0: return

    if useRegex:
        # Match regular expression
        let pattern =
            try: re2((if matchCase: "" else: "(?i)") & query)
            except CatchableError: return

        for i, item in component.content.items:
            for m in ($item.getText()).findAll(pattern):
                result.add((line: i, a: m.boundaries.a, b: m.boundaries.b + 1))
    else:
        # Perform regular search
        let searchQuery = if matchCase: query else: query.toLowerAscii()
        for i, item in component.content.items:
            let text = if matchCase: $item.getText() else: ($item.getText()).toLowerAscii()
            var pos = 0
            while pos < text.len:
                let idx = text.find(searchQuery, pos)
                if idx < 0: break
                result.add((line: i, a: idx, b: idx + query.len()))
                pos = idx + 1

# Drawing
proc print(component: TextareaWidget, item: ConsoleItem, spans: seq[tuple[a: int, b: int]], currentSpan: tuple[a: int, b: int]) =
    let drawList = igGetWindowDrawList()
    let cursorPos = igGetCursorScreenPos()
    let lineHeight = igGetTextLineHeightWithSpacing()

    # Draw highlight over matched word
    if spans.len > 0:
        let text = $item.getText()
        for span in spans:
            let color = if span == currentSpan: SEARCH_CURRENT_MATCH else: SEARCH_MATCH
            let x0 = cursorPos.x + igCalcTextSize(text[0..<span.a].cstring, nil, false, 0.0f).x
            let x1 = cursorPos.x + igCalcTextSize(text[0..<span.b].cstring, nil, false, 0.0f).x
            drawList.ImDrawList_AddRectFilled(ImVec2(x: x0, y: cursorPos.y), ImVec2(x: x1, y: cursorPos.y + lineHeight), color, 0.0f, 0)

    if item.itemType != LOG_OUTPUT and component.showTimestamps:
        igTextColored(GRAY, ("[" & item.timestamp & "]").cstring, nil)
        igSameLine(0.0f, 0.0f)

    case item.itemType:
    of LOG_INFO, LOG_INFO_SHORT:
        igTextColored(CONSOLE_INFO, ($item.itemType).cstring)
    of LOG_ERROR, LOG_ERROR_SHORT:
        igTextColored(CONSOLE_ERROR, ($item.itemType).cstring)
    of LOG_SUCCESS, LOG_SUCCESS_SHORT:
        igTextColored(CONSOLE_SUCCESS, ($item.itemType).cstring)
    of LOG_WARNING, LOG_WARNING_SHORT:
        igTextColored(CONSOLE_WARNING, ($item.itemType).cstring)
    of LOG_COMMAND, LOG_COMMAND_SHORT:
        igTextColored(CONSOLE_COMMAND, ($item.itemType).cstring)
    of LOG_OUTPUT:
        igTextColored(vec4(0.0f, 0.0f, 0.0f, 0.0f), ($item.itemType).cstring)

    igSameLine(0.0f, 0.0f)

    if not item.highlight:
        igTextUnformatted(item.text.cstring, nil)
    else:
        igTextColored(CONSOLE_HIGHLIGHT, item.text.cstring)

proc draw*(component: TextareaWidget, size: ImVec2, matches: seq[tuple[line: int, a: int, b: int]] = @[], currentMatch: int = -1, scrollToMatch: ptr bool = nil) =
    try:
        igPushStyleColor_Vec4(ImGui_Col_FrameBg.int32, vec4(0.1f, 0.1f, 0.1f, 1.0f))
        igPushStyleColor_Vec4(ImGui_Col_ScrollbarBg.int32, vec4(0.1f, 0.1f, 0.1f, 1.0f))
        igPushStyleColor_Vec4(ImGui_Col_Border.int32, vec4(0.2f, 0.2f, 0.2f, 1.0f))
        igPushStyleVar_Float(ImGui_StyleVar_FrameBorderSize.int32, 1.0f)

        let flags = ImGuiChildFlags_NavFlattened.int32 or ImGui_ChildFlags_Borders.int32 or ImGui_ChildFlags_AlwaysUseWindowPadding.int32 or ImGuiChildFlags_FrameStyle.int32
        if igBeginChild_Str("##TextArea", size, flags, ImGuiWindowFlags_HorizontalScrollbar.int32):

            var spanLookup = initTable[int, seq[tuple[a: int, b: int]]]()
            for match in matches:
                spanLookup.mgetOrPut(match.line, @[]).add((a: match.a, b: match.b))

            let currentMatchLine =
                if currentMatch >= 0 and currentMatch < matches.len(): matches[currentMatch].line
                else: -1
                
            let currentSpan =
                if currentMatch >= 0 and currentMatch < matches.len(): (a: matches[currentMatch].a, b: matches[currentMatch].b)
                else: (a: -1, b: -1)

            var scrolledToMatch = false
            for i, item in component.content.items:
                let spans = spanLookup.getOrDefault(i, @[])

                if i == currentMatchLine and not scrollToMatch.isNil and scrollToMatch[]:
                    igSetScrollHereY(0.5f)
                    scrollToMatch[] = false
                    scrolledToMatch = true

                component.print(item, spans, if i == currentMatchLine: currentSpan else: (a: -1, b: -1))

            if component.autoScroll and not scrolledToMatch:
                if igGetScrollY() >= igGetScrollMaxY():
                    igSetScrollHereY(1.0f)

            # Fix text-selection for imguin >= 1.92.7.0: textselect_update() adds DC.Indent.x to cursorPosStart.x, but GetCursorStartPos() already includes it
            igUnindent(igGetStyle().FramePadding.x)
            component.textSelect.textselect_update()

    except IndexDefect:
        # CTRL+A crashes when no items are in the text area
        discard

    finally:
        igPopStyleColor(3)
        igPopStyleVar(1)
        igEndChild()
