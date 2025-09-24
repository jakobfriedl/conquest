import strutils
import imguin/[cimgui, glfw_opengl, simple]
import ../../utils/[appImGui, colors]
import ../../../common/[types, utils]

type 
    Direction = enum
        Right = 0
        Left = 1

    DualListSelectionComponent* = ref object of RootObj
        items: array[2, seq[string]]
        selection: array[2, ptr ImGuiSelectionBasicStorage]

proc DualListSelection*(items: seq[string]): DualListSelectionComponent = 
    result = new DualListSelectionComponent
    result.items[0] = items
    result.items[1] = @[]
    result.selection[0] = ImGuiSelectionBasicStorage_ImGuiSelectionBasicStorage()
    result.selection[1] = ImGuiSelectionBasicStorage_ImGuiSelectionBasicStorage()

proc moveAll(component: DualListSelectionComponent, direction: Direction) = 
    
    if direction == Right: 
        for m in component.items[0]: 
            component.items[1].add(m)
        component.items[0].setLen(0)

        ImGuiSelectionBasicStorage_Swap(component.selection[0], component.selection[1])
        ImGuiSelectionBasicStorage_Clear(component.selection[0])

    else: 
        for m in component.items[1]: 
            component.items[0].add(m)
        component.items[1].setLen(0)

        ImGuiSelectionBasicStorage_Swap(component.selection[1], component.selection[0])
        ImGuiSelectionBasicStorage_Clear(component.selection[1])

proc moveSelection(component: DualListSelectionComponent, direction: Direction) = 
    
    if direction == Right: 
        var 
            keep: seq[string]

        for i in 0 ..< component.items[0].len(): 
            let item = component.items[0][i]
            if not component.selection[0].ImGuiSelectionBasicStorage_Contains(cast[ImGuiID](i)):
                keep.add(item)
                continue
            component.items[1].add(item)
        component.items[0] = keep

        ImGuiSelectionBasicStorage_Swap(component.selection[0], component.selection[1])
        ImGuiSelectionBasicStorage_Clear(component.selection[0])

    else: 
        var 
            keep: seq[string]

        for i in 0 ..< component.items[1].len(): 
            let item = component.items[1][i]
            if not component.selection[1].ImGuiSelectionBasicStorage_Contains(cast[ImGuiID](i)):
                keep.add(item)
                continue
            component.items[0].add(item)
        component.items[1] = keep

        ImGuiSelectionBasicStorage_Swap(component.selection[1], component.selection[0])
        ImGuiSelectionBasicStorage_Clear(component.selection[1])

proc draw*(component: DualListSelectionComponent) = 

    if igBeginTable("split", 3, ImGuiTableFlags_None.int32, vec2(0.0f, 0.0f), 0.0f): 

        igTableSetupColumn("", ImGuiTableColumnFlags_WidthStretch.int32, 0.0f, 0) # Left
        igTableSetupColumn("", ImGuiTableColumnFlags_WidthFixed.int32, 0.0f, 0)   # Buttons
        igTableSetupColumn("", ImGuiTableColumnFlags_WidthStretch.int32, 0.0f, 0) # Right
        igTableNextRow(ImGuiTableRowFlags_None.int32, 0.0f)

        var containerHeight: float

        # Left selection container
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
                discard igSelectable_Bool(modules[row], isSelected, ImGuiSelectableFlags_AllowDoubleClick.int32, vec2(0.0f, 0.0f))

            multiSelectIO = igEndMultiSelect()
            ImGuiSelectionBasicStorage_ApplyRequests(selection, multiSelectIO)

        igEndChild()

        # Buttons column 
        igTableSetColumnIndex(1)
        igNewLine() 

        let buttonSize = vec2(igGetFrameHeight(), igGetFrameHeight())
        if igButton(">>", buttonSize): 
            component.moveAll(Right)
        if igButton(">", buttonSize): 
            component.moveSelection(Right)
        if igButton("<", buttonSize): 
            component.moveSelection(Left)
        if igButton("<<", buttonSize): 
            component.moveAll(Left)

        # Right selection container
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
                discard igSelectable_Bool(modules[row], isSelected, ImGuiSelectableFlags_AllowDoubleClick.int32, vec2(0.0f, 0.0f))

            multiSelectIO = igEndMultiSelect()
            ImGuiSelectionBasicStorage_ApplyRequests(selection, multiSelectIO)

        igEndChild()


        igEndTable()