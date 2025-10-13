import strutils, sequtils, algorithm
import imguin/[cimgui, glfw_opengl, simple]
import ../../utils/[appImGui, colors, utils]
import ../../../common/[types, utils]

type 
    DualListSelectionWidget*[T] = ref object of RootObj
        items*: array[2, seq[T]]
        selection: array[2, ptr ImGuiSelectionBasicStorage]
        display: proc(item: T): string
        compare: proc(x, y: T): int
        tooltip: proc(item: T): string

proc defaultDisplay[T](item: T): string = 
    return $item

proc DualListSelection*[T](items: seq[T], display: proc(item: T): string = defaultDisplay, compare: proc(x, y: T): int,  tooltip: proc(item: T): string = nil): DualListSelectionWidget[T] = 
    result = new DualListSelectionWidget[T]
    result.items[0] = items
    result.items[1] = @[]
    result.selection[0] = ImGuiSelectionBasicStorage_ImGuiSelectionBasicStorage()
    result.selection[1] = ImGuiSelectionBasicStorage_ImGuiSelectionBasicStorage()
    result.display = display
    result.compare = compare
    result.tooltip = tooltip

proc moveAll[T](component: DualListSelectionWidget[T], src, dst: int) = 
    for m in component.items[src]: 
        component.items[dst].add(m)
    component.items[dst].sort(component.compare)
    component.items[src].setLen(0)

    ImGuiSelectionBasicStorage_Swap(component.selection[src], component.selection[dst])
    ImGuiSelectionBasicStorage_Clear(component.selection[src])

proc moveSelection[T](component: DualListSelectionWidget[T], src, dst: int) = 
    var keep: seq[T]
    for i in 0 ..< component.items[src].len(): 
        let item = component.items[src][i]
        if not component.selection[src].ImGuiSelectionBasicStorage_Contains(cast[ImGuiID](i)):
            keep.add(item)
            continue
        component.items[dst].add(item)
    component.items[dst].sort(component.compare)
    component.items[src] = keep

    ImGuiSelectionBasicStorage_Swap(component.selection[src], component.selection[dst])
    ImGuiSelectionBasicStorage_Clear(component.selection[src])

proc reset*[T](component: DualListSelectionWidget[T]) = 
    component.moveAll(1, 0)

proc draw*[T](component: DualListSelectionWidget[T]) = 

    if igBeginTable("split", 3, ImGuiTableFlags_None.int32, vec2(0.0f, 0.0f), 0.0f): 

        igTableSetupColumn("", ImGuiTableColumnFlags_WidthStretch.int32, 0.0f, 0) # Left
        igTableSetupColumn("", ImGuiTableColumnFlags_WidthFixed.int32, 0.0f, 0)   # Buttons
        igTableSetupColumn("", ImGuiTableColumnFlags_WidthStretch.int32, 0.0f, 0) # Right
        igTableNextRow(ImGuiTableRowFlags_None.int32, 0.0f)

        var containerHeight: float

        # Left selection column
        igTableSetColumnIndex(0) 
            
        var modules = component.items[0]
        var selection = component.selection[0]

        # Header
        var text = "Available"
        var textSize: ImVec2
        igCalcTextSize(addr textSize, text, nil, false, 0.0f)
        igSetCursorPosX(igGetCursorPosX() + (igGetColumnWidth(0) - textSize.x) * 0.5f)
        igTextColored(GRAY, text)
        
        # Set the size of selection box to fit all modules
        igSetNextWindowContentSize(vec2(0.0f, float(modules.len()) * igGetTextLineHeightWithSpacing()))
        igSetNextWindowSizeConstraints(vec2(0.0f, igGetTextLineHeightWithSpacing() * 10.0f), vec2(igGET_FLT_MAX(), igGET_FLT_MAX()), nil, nil) # Set minimum container size
        if igBeginChild_Str("0", vec2(0.0f, -1.0f), ImGuiChildFlags_FrameStyle.int32 or ImGuiChildFlags_ResizeY.int32, ImGuiWindowFlags_None.int32):
            containerHeight = igGetWindowHeight() 

            var multiSelectIO = igBeginMultiSelect(ImGuiMultiSelectFlags_None.int32, selection[].Size, int32(modules.len())) 
            ImGuiSelectionBasicStorage_ApplyRequests(selection, multiSelectIO)
            
            for row in 0 ..< modules.len().int32: 
                var isSelected = ImGuiSelectionBasicStorage_Contains(selection, cast[ImGuiID](row))
                igSetNextItemSelectionUserData(row)
                discard igSelectable_Bool(component.display(modules[row]), isSelected, ImGuiSelectableFlags_AllowDoubleClick.int32, vec2(0.0f, 0.0f))
                
                if not component.tooltip.isNil():
                    setTooltip(component.tooltip(modules[row]))

                # Move on Enter and double-click
                if igIsItemFocused(): 
                    if igIsKeyPressed_Bool(ImGuiKey_Enter, false) or igIsKeyPressed_Bool(ImGuiKey_KeypadEnter, false):
                        component.moveSelection(0, 1)
                    if igIsMouseDoubleClicked_Nil(ImGui_MouseButton_Left.int32):
                        component.moveSelection(0, 1)

            multiSelectIO = igEndMultiSelect()
            ImGuiSelectionBasicStorage_ApplyRequests(selection, multiSelectIO)

        igEndChild()

        # Buttons column 
        igTableSetColumnIndex(1)
        igNewLine() 

        let buttonSize = vec2(igGetFrameHeight(), igGetFrameHeight())
        if igButton(">>", buttonSize): 
            component.moveAll(0, 1)
        if igButton(">", buttonSize): 
            component.moveSelection(0, 1)
        if igButton("<", buttonSize): 
            component.moveSelection(1, 0)
        if igButton("<<", buttonSize): 
            component.moveAll(1, 0)

        # Right selection column
        igTableSetColumnIndex(2) 
            
        modules = component.items[1]
        selection = component.selection[1]

        # Header
        text = "Selected"
        igCalcTextSize(addr textSize, text, nil, false, 0.0f)
        igSetCursorPosX(igGetCursorPosX() + (igGetColumnWidth(2) - textSize.x) * 0.5f)
        igTextColored(GRAY, text)
        
        # Set the size of selection box to fit all modules
        igSetNextWindowContentSize(vec2(0.0f, float(modules.len()) * igGetTextLineHeightWithSpacing()))
        if igBeginChild_Str("1", vec2(0.0f, containerHeight), ImGuiChildFlags_FrameStyle.int32, ImGuiWindowFlags_None.int32): 

            var multiSelectIO = igBeginMultiSelect(ImGuiMultiSelectFlags_None.int32, selection[].Size, int32(modules.len())) 
            ImGuiSelectionBasicStorage_ApplyRequests(selection, multiSelectIO)

            for row in 0 ..< modules.len().int32:         
                var isSelected = ImGuiSelectionBasicStorage_Contains(selection, cast[ImGuiID](row))
                igSetNextItemSelectionUserData(row)
                discard igSelectable_Bool(component.display(modules[row]), isSelected, ImGuiSelectableFlags_AllowDoubleClick.int32, vec2(0.0f, 0.0f))

                if not component.tooltip.isNil():
                    setTooltip(component.tooltip(modules[row]))

                # Move on Enter and double-click
                if igIsItemFocused(): 
                    if igIsKeyPressed_Bool(ImGuiKey_Enter, false) or igIsKeyPressed_Bool(ImGuiKey_KeypadEnter, false):
                        component.moveSelection(1, 0)
                    if igIsMouseDoubleClicked_Nil(ImGui_MouseButton_Left.int32):
                        component.moveSelection(1, 0)

            multiSelectIO = igEndMultiSelect()
            ImGuiSelectionBasicStorage_ApplyRequests(selection, multiSelectIO)

        igEndChild()

        igEndTable()