import imguin/[cimgui, glfw_opengl]
import tables, sets, sequtils, native_dialogs, algorithm
import ../utils/appImGui
import ../core/scripting/engine
import ../core/database
import ../../types/client
 
proc ModuleManager*(title: string, showComponent: ptr bool): ModuleManagerComponent = 
    result = new ModuleManagerComponent
    result.title = title
    result.showComponent = showComponent
    result.scripts = initHashSet[string]()
    result.modules = initTable[string, Module]()
    result.groups = initOrderedTable[string, OrderedTable[string, Command]]()
    result.selection = ImGuiSelectionBasicStorage_ImGuiSelectionBasicStorage()

proc draw*(component: ModuleManagerComponent) = 
    igBegin(component.title.cstring, component.showComponent, 0)
    defer: igEnd() 
    
    let textSpacing = igGetStyle().ItemSpacing.x    
    
    if igButton("Load Script", vec2(0.0f, 0.0f)):          
        let path = callDialogFileSave("Load Script") 
        loadScript(path)
        component.scripts.incl(path)
    
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
    
    let cols: int32 = 1
    if igBeginTable("Modules", cols, tableFlags, vec2(0.0f, 0.0f), 0.0f):
        
        igTableSetupColumn("Script Path", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupScrollFreeze(0, 1)
        igTableHeadersRow()
        
        var multiSelectIO = igBeginMultiSelect(
            ImGuiMultiSelectFlags_ClearOnEscape.int32 or ImGuiMultiSelectFlags_BoxSelect1d.int32, 
            component.selection[].Size, 
            int32(component.scripts.len)
        )
        ImGuiSelectionBasicStorage_ApplyRequests(component.selection, multiSelectIO)
        
        # Convert set to seq for indexed iteration
        let scripts = component.scripts.items.toSeq()
        for i, path in scripts: 
            igTableNextRow(ImGuiTableRowFlags_None.int32, 0.0f)
            if igTableSetColumnIndex(0):          
                igSetNextItemSelectionUserData(i)
                var isSelected = ImGuiSelectionBasicStorage_Contains(component.selection, cast[ImGuiID](i))
                discard igSelectable_Bool(path.cstring, isSelected, ImGuiSelectableFlags_SpanAllColumns.int32, vec2(0.0f, 0.0f))
            
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
                        if dbRemoveScript(path):
                            component.scripts.excl(path)
                ImGuiSelectionBasicStorage_Clear(component.selection)
                igCloseCurrentPopup()
                
            igEndPopup()
            
        multiSelectIO = igEndMultiSelect()
        ImGuiSelectionBasicStorage_ApplyRequests(component.selection, multiSelectIO)
        igEndTable()