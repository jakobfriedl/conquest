import strutils
import imguin/[cimgui, glfw_opengl, simple]
import ../utils/appImGui
import ../../common/[types, utils]
import ./modals/startListener

type 
    ListenersTableComponent = ref object of RootObj
        title: string 
        listeners: seq[Listener]
        selection: ptr ImGuiSelectionBasicStorage
        startListenerModal: ListenerModalComponent

let exampleListeners: seq[Listener] = @[
    Listener(
        listenerId: "L1234567",
        address: "192.168.1.1",
        port: 8080,
        protocol: HTTP
    ),
    Listener(
        listenerId: "L7654321",
        address: "10.0.0.2",
        port: 443,
        protocol: HTTP
    )
]

proc ListenersTable*(title: string): ListenersTableComponent = 
    result = new ListenersTableComponent
    result.title = title
    result.listeners = exampleListeners
    result.selection = ImGuiSelectionBasicStorage_ImGuiSelectionBasicStorage()
    result.startListenerModal = ListenerModal()

proc draw*(component: ListenersTableComponent, showComponent: ptr bool) = 
    igBegin(component.title, showComponent, 0)
    defer: igEnd() 

    let textSpacing = igGetStyle().ItemSpacing.x    

    # Listener creation modal
    if igButton("Start Listener", vec2(0.0f, 0.0f)):          
        igOpenPopup_str("Start Listener", ImGui_PopupFlags_None.int32) 

    let listener = component.startListenerModal.draw()
    if listener != nil: 
        # TODO: Start listener
        
        component.listeners.add(listener)    

    #[
        Listener table
    ]#
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
        ImGui_TableFlags_SizingStretchProp.int32
    )

    let cols: int32 = 4
    if igBeginTable("Listeners", cols, tableFlags, vec2(0.0f, 0.0f), 0.0f):

        igTableSetupColumn("ListenerID", ImGuiTableColumnFlags_NoReorder.int32 or ImGuiTableColumnFlags_NoHide.int32, 0.0f, 0)
        igTableSetupColumn("Address", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Port", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Protocol", ImGuiTableColumnFlags_None.int32, 0.0f, 0)

        igTableSetupScrollFreeze(0, 1)
        igTableHeadersRow()
        
        var multiSelectIO = igBeginMultiSelect(ImGuiMultiSelectFlags_ClearOnEscape.int32 or ImGuiMultiSelectFlags_BoxSelect1d.int32, component.selection[].Size, int32(component.listeners.len())) 
        ImGuiSelectionBasicStorage_ApplyRequests(component.selection, multiSelectIO)

        for row in 0 ..< component.listeners.len(): 
            
            igTableNextRow(ImGuiTableRowFlags_None.int32, 0.0f)
            let listener = component.listeners[row]

            if igTableSetColumnIndex(0):          
                # Enable multi-select functionality       
                igSetNextItemSelectionUserData(row)
                var isSelected = ImGuiSelectionBasicStorage_Contains(component.selection, cast[ImGuiID](row))
                discard igSelectable_Bool(listener.listenerId, isSelected, ImGuiSelectableFlags_SpanAllColumns.int32, vec2(0.0f, 0.0f))
                
            if igTableSetColumnIndex(1): 
                igText(listener.address)
            if igTableSetColumnIndex(2): 
                igText($listener.port)
            if igTableSetColumnIndex(3): 
                igText($listener.protocol)

        # Handle right-click context menu
        # Right-clicking the table header to hide/show columns or reset the layout is only possible when no sessions are selected
        if component.selection[].Size > 0 and igBeginPopupContextWindow("TableContextMenu", ImGui_PopupFlags_MouseButtonRight.int32): 
            
            if igMenuItem("Stop", nil, false, true): 
                # Update agents table with only non-selected ones
                var newListeners: seq[Listener] = @[]
                for i in 0 ..< component.listeners.len():
                    if not ImGuiSelectionBasicStorage_Contains(component.selection, cast[ImGuiID](i)):
                        newListeners.add(component.listeners[i])

                # TODO: Stop/kill listener

                component.listeners = newListeners
                ImGuiSelectionBasicStorage_Clear(component.selection)
                igCloseCurrentPopup()

            igEndPopup()

        multiSelectIO = igEndMultiSelect()
        ImGuiSelectionBasicStorage_ApplyRequests(component.selection, multiSelectIO)
        
        igEndTable()