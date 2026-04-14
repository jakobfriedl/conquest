import imguin/[cimgui, glfw_opengl]
import tables, sequtils, strformat
import ../utils/[appImGui, dialogs]
import ../core/scripting/engine
import ../core/database
import ../../types/client
 
proc ScriptManager*(title: string, showComponent: ptr bool): ScriptManagerComponent = 
    result = new ScriptManagerComponent
    result.title = title
    result.showComponent = showComponent
    result.scripts = initOrderedTable[string, tuple[active: bool, error: string]]()
    result.modules = initTable[string, Module]()
    result.groups = initOrderedTable[string, OrderedTable[string, Command]]()
    result.selection = ImGuiSelectionBasicStorage_ImGuiSelectionBasicStorage()

proc draw*(component: ScriptManagerComponent) = 
    igBegin(component.title.cstring, component.showComponent, 0)
    defer: igEnd() 
    
    let textSpacing = igGetStyle().ItemSpacing.x    
    
    if igButton("Load Script", vec2(0.0f, 0.0f)):          
        let paths = callDialogFileOpenMultiple("Load Scripts", "", [("Python Files (*.py)", "*.py")])
        for path in paths:
            loadScript(path)
    
    igSameLine(0.0f, textSpacing)

    if igButton("Reload All", vec2(0.0f, 0.0f)):
        for path in component.scripts.keys().toSeq():
            loadScript(path)

    let tableFlags = (
        ImGuiTableFlags_Resizable.int32 or 
        ImGuiTableFlags_Reorderable.int32 or 
        ImGuiTableFlags_Hideable.int32 or 
        ImGuiTableFlags_HighlightHoveredColumn.int32 or 
        ImGuiTableFlags_RowBg.int32 or 
        ImGuiTableFlags_BordersV.int32 or 
        ImGuiTableFlags_BordersH.int32 or 
        ImGuiTableFlags_ScrollY.int32 or
        ImGuiTableFlags_ScrollX.int32 or 
        ImGuiTableFlags_NoBordersInBodyUntilResize.int32 or
        ImGui_TableFlags_SizingStretchSame.int32
    )
    
    let cols: int32 = 2
    if igBeginTable("Modules", cols, tableFlags, vec2(0.0f, 0.0f), 0.0f):
        
        igTableSetupColumn("Script Path", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Status", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupScrollFreeze(0, 1)
        igTableHeadersRow()
        
        var multiSelectIO = igBeginMultiSelect(
            ImGuiMultiSelectFlags_ClearOnEscape.int32 or ImGuiMultiSelectFlags_BoxSelect1d.int32, 
            component.selection[].Size, 
            int32(component.scripts.len)
        )
        ImGuiSelectionBasicStorage_ApplyRequests(component.selection, multiSelectIO)
        
        let scripts = component.scripts.keys().toSeq()
        for i, path in scripts:
            let (active, error) = component.scripts[path]
            igTableNextRow(ImGuiTableRowFlags_None.int32, 0.0f)
            if igTableSetColumnIndex(0):
                igSetNextItemSelectionUserData(i.int32)
                var isSelected = ImGuiSelectionBasicStorage_Contains(component.selection, cast[ImGuiID](i))

                if not active:
                    igPushStyleColor_Vec4(ImGui_Col_Text.cint, CONSOLE_ERROR)

                discard igSelectable_Bool(path.cstring, isSelected, ImGuiSelectableFlags_SpanAllColumns.int32, vec2(0.0f, 0.0f))

                if igTableSetColumnIndex(1): 
                    igText(if active: "Active".cstring else: fmt"Error: {error}".cstring)

                if not active:
                    igPopStyleColor(1)

        # Handle right-click context menu
        if component.selection[].Size > 0 and igBeginPopupContextWindow("TableContextMenu", ImGui_PopupFlags_MouseButtonRight.int32): 
            if igMenuItem("Reload", nil, false, true): 
                for i, path in scripts:
                    if ImGuiSelectionBasicStorage_Contains(component.selection, cast[ImGuiID](i)):
                        # Reload python script
                        loadScript(path)

                ImGuiSelectionBasicStorage_Clear(component.selection)
                igCloseCurrentPopup()
                
            if igMenuItem("Remove", nil, false, true):
                for i, path in scripts:
                    if ImGuiSelectionBasicStorage_Contains(component.selection, cast[ImGuiID](i)):
                        # Delete script
                        if dbRemoveScript(path):
                            component.scripts.del(path)
                ImGuiSelectionBasicStorage_Clear(component.selection)
                igCloseCurrentPopup()
                
            igEndPopup()
            
        multiSelectIO = igEndMultiSelect()
        ImGuiSelectionBasicStorage_ApplyRequests(component.selection, multiSelectIO)
        igEndTable()