import imguin/[cimgui, glfw_opengl]
import tables, native_dialogs, sequtils
import ../utils/appImGui
import ../core/scripting/engine
import ../core/database
import ../context
import ../../common/types

# type 
#     ModuleManagerComponent* = ref object of RootObj
#         title: string 
#         modules: seq[tuple[name, description, path: string, commandCount: int]]
        
proc ModuleManager*(title: string): ModuleManagerComponent = 
    result = new ModuleManagerComponent
    result.title = title
    result.modules = initTable[string, tuple[name, description, path: string, commandCount: int]]()
    result.selection = ImGuiSelectionBasicStorage_ImGuiSelectionBasicStorage()

proc draw*(component: ModuleManagerComponent, showComponent: ptr bool) = 
    igBegin(component.title.cstring, showComponent, 0)
    defer: igEnd() 

    let textSpacing = igGetStyle().ItemSpacing.x    
    if igButton("Load Module", vec2(0.0f, 0.0f)):          
        let path = callDialogFileSave("Load Module") 
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

    let cols: int32 = 4
    if igBeginTable("Modules", cols, tableFlags, vec2(0.0f, 0.0f), 0.0f):
        
        igTableSetupColumn("Name", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Description", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Commands", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Path", ImGuiTableColumnFlags_None.int32, 0.0f, 0)

        igTableSetupScrollFreeze(0, 1)
        igTableHeadersRow()

        var multiSelectIO = igBeginMultiSelect(ImGuiMultiSelectFlags_ClearOnEscape.int32 or ImGuiMultiSelectFlags_BoxSelect1d.int32, component.selection[].Size, int32(component.modules.len())) 
        ImGuiSelectionBasicStorage_ApplyRequests(component.selection, multiSelectIO)

        let modules = component.modules.values().toSeq()
        for i, module in modules: 
            
            igTableNextRow(ImGuiTableRowFlags_None.int32, 0.0f)

            if igTableSetColumnIndex(0):          
                igSetNextItemSelectionUserData(i)
                var isSelected = ImGuiSelectionBasicStorage_Contains(component.selection, cast[ImGuiID](i))
                discard igSelectable_Bool(module.name.cstring, isSelected, ImGuiSelectableFlags_SpanAllColumns.int32, vec2(0.0f, 0.0f))

            if igTableSetColumnIndex(1): 
                igText(module.description.cstring)

            if igTableSetColumnIndex(2): 
                igText(($module.commandCount).cstring)

            if igTableSetColumnIndex(3): 
                igText(module.path.cstring)
            
        # Handle right-click context menu
        if component.selection[].Size > 0 and igBeginPopupContextWindow("TableContextMenu", ImGui_PopupFlags_MouseButtonRight.int32): 

            if igMenuItem("Reload", nil, false, true): 
                for i, module in modules:
                    if ImGuiSelectionBasicStorage_Contains(component.selection, cast[ImGuiID](i)):
                        # Reload python script
                        loadScript(module.path)
                ImGuiSelectionBasicStorage_Clear(component.selection)
                igCloseCurrentPopup()

            if igMenuItem("Remove", nil, false, true): 
                for i, module in modules:
                    if ImGuiSelectionBasicStorage_Contains(component.selection, cast[ImGuiID](i)):
                        if dbRemoveModule(module.name):
                            component.modules.del(module.name)
                ImGuiSelectionBasicStorage_Clear(component.selection)
                igCloseCurrentPopup()

            igEndPopup()

        multiSelectIO = igEndMultiSelect()
        ImGuiSelectionBasicStorage_ApplyRequests(component.selection, multiSelectIO)

        igEndTable()