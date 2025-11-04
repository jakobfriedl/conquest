import strutils
import imguin/[cimgui, glfw_opengl, simple]
import ./modals/[startListener, generatePayload]
import ../utils/appImGui
import ../core/websocket
import ../../common/types

type 
    ListenersTableComponent* = ref object of RootObj
        title: string 
        listeners*: seq[UIListener]
        selection: ptr ImGuiSelectionBasicStorage
        startListenerModal: ListenerModalComponent
        generatePayloadModal*: AgentModalComponent

proc ListenersTable*(title: string): ListenersTableComponent = 
    result = new ListenersTableComponent
    result.title = title
    result.listeners = @[]
    result.selection = ImGuiSelectionBasicStorage_ImGuiSelectionBasicStorage()
    result.startListenerModal = ListenerModal()
    result.generatePayloadModal = AgentModal()

proc draw*(component: ListenersTableComponent, showComponent: ptr bool, connection: WsConnection) = 
    igBegin(component.title.cstring, showComponent, 0)
    defer: igEnd() 

    let textSpacing = igGetStyle().ItemSpacing.x    

    # Listener creation modal
    if igButton("Start Listener", vec2(0.0f, 0.0f)):          
        igOpenPopup_str("Start Listener", ImGui_PopupFlags_None.int32) 
    igSameLine(0.0f, textSpacing)

    # Payload generation modal (only enabled when at least one listener is active)
    igBeginDisabled(component.listeners.len() <= 0)
    if igButton("Generate Payload", vec2(0.0f, 0.0f)):  
        component.generatePayloadModal.show = true        
        igOpenPopup_str("Generate Payload", ImGui_PopupFlags_None.int32) 
    igEndDisabled()

    let listener = component.startListenerModal.draw()
    if listener != nil: 
        connection.sendStartListener(listener)

    let buildInformation = component.generatePayloadModal.draw(component.listeners)
    if buildInformation != nil:
        connection.sendAgentBuild(buildInformation)

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
        ImGui_TableFlags_SizingStretchSame.int32
    )

    let cols: int32 = 5
    if igBeginTable("Listeners", cols, tableFlags, vec2(0.0f, 0.0f), 0.0f):

        igTableSetupColumn("ListenerID", ImGuiTableColumnFlags_NoReorder.int32 or ImGuiTableColumnFlags_NoHide.int32, 0.0f, 0)
        igTableSetupColumn("Address", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Port", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Callback Hosts", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Protocol", ImGuiTableColumnFlags_None.int32, 0.0f, 0)

        igTableSetupScrollFreeze(0, 1)
        igTableHeadersRow()
        
        var multiSelectIO = igBeginMultiSelect(ImGuiMultiSelectFlags_ClearOnEscape.int32 or ImGuiMultiSelectFlags_BoxSelect1d.int32, component.selection[].Size, int32(component.listeners.len())) 
        ImGuiSelectionBasicStorage_ApplyRequests(component.selection, multiSelectIO)

        for i, listener in component.listeners: 
            
            igTableNextRow(ImGuiTableRowFlags_None.int32, 0.0f)

            if igTableSetColumnIndex(0):          
                # Enable multi-select functionality       
                igSetNextItemSelectionUserData(i)
                var isSelected = ImGuiSelectionBasicStorage_Contains(component.selection, cast[ImGuiID](i))
                discard igSelectable_Bool(listener.listenerId.cstring, isSelected, ImGuiSelectableFlags_SpanAllColumns.int32, vec2(0.0f, 0.0f))
                
            if igTableSetColumnIndex(1): 
                igText(listener.address.cstring)
            if igTableSetColumnIndex(2): 
                igText(($listener.port).cstring)
            if igTableSetColumnIndex(3): 
                for host in listener.hosts.split(";"):
                    igText(host.cstring)
            if igTableSetColumnIndex(4): 
                igText(($listener.protocol).cstring)

        # Handle right-click context menu
        # Right-clicking the table header to hide/show columns or reset the layout is only possible when no sessions are selected
        if component.selection[].Size > 0 and igBeginPopupContextWindow("TableContextMenu", ImGui_PopupFlags_MouseButtonRight.int32): 
            
            if igMenuItem("Stop", nil, false, true): 
                # Update agents table with only non-selected ones
                var newListeners: seq[UIListener] = @[]
                for i, listener in component.listeners:
                    if not ImGuiSelectionBasicStorage_Contains(component.selection, cast[ImGuiID](i)):
                        newListeners.add(listener)
                    else: 
                        connection.sendStopListener(listener.listenerId)

                component.listeners = newListeners
                ImGuiSelectionBasicStorage_Clear(component.selection)
                igCloseCurrentPopup()

            igEndPopup()

        multiSelectIO = igEndMultiSelect()
        ImGuiSelectionBasicStorage_ApplyRequests(component.selection, multiSelectIO)
        
        igEndTable()