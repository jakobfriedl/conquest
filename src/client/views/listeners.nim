import strutils, sequtils, tables
import imguin/[cimgui, glfw_opengl, simple]
import ./modals/[startListener, generatePayload]
import ./widgets/textarea
import ../utils/[appImGui, globals]
import ../core/websocket
import ../../types/[common, client]

proc ListenersTable*(title: string, showComponent: ptr bool): ListenersTableComponent = 
    result = new ListenersTableComponent
    result.title = title
    result.showComponent = showComponent
    result.listeners = initTable[string, UIListener]() 
    result.startListenerModal = ListenerModal()
    result.generatePayloadModal = PayloadModal()
    result.profilePreview = Textarea(showTimestamps = false, autoScroll = false)

proc draw*(component: ListenersTableComponent) = 
    igBegin(component.title.cstring, component.showComponent, 0)
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

    let listeners = component.listeners.values().toSeq()

    let listener = component.startListenerModal.draw()
    if listener != nil: 
        cq.connection.sendStartListener(listener)

    let buildInformation = component.generatePayloadModal.draw(listeners)
    if buildInformation != nil:
        cq.connection.sendAgentBuild(buildInformation)

    # Profile TOML Preview
    if component.showProfilePreview:
        igOpenPopup_str("Profile", ImGui_PopupFlags_None.int32)
    
    igSetNextWindowSize(vec2(600.0f, 800.0f), ImGuiCond_Always.int32)
    if igBeginPopupModal("Profile", addr component.showProfilePreview, ImGuiWindowFlags_NoResize.int32):
        component.profilePreview.draw(vec2(0.0f, 0.0f))
        igEndPopup()

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

    let cols: int32 = 7
    if igBeginTable("Listeners", cols, tableFlags, vec2(0.0f, 0.0f), 0.0f):

        igTableSetupColumn("ListenerID", ImGuiTableColumnFlags_NoReorder.int32 or ImGuiTableColumnFlags_NoHide.int32, 0.0f, 0)
        igTableSetupColumn("Name", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Protocol", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Bind Address", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Bind Port", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Callback", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("##Actions", ImGuiTableColumnFlags_NoReorder.int32 or ImGuiTableColumnFlags_NoHide.int32, 0.0f, 0)

        igTableSetupScrollFreeze(0, 1)
        igTableHeadersRow()
        
        for i, listener in listeners:
            igTableNextRow(ImGuiTableRowFlags_None.int32, 0.0f)

            if igTableSetColumnIndex(0):
                igText(listener.listenerId.cstring)
            if igTableSetColumnIndex(1):
                igText(listener.name.cstring)
            if igTableSetColumnIndex(2):
                igText(($listener.listenerType).cstring)
            if igTableSetColumnIndex(3):
                if listener.listenerType == LISTENER_HTTP:
                    igText(listener.address.cstring)
                else:
                    igText("-")
            if igTableSetColumnIndex(4):
                if listener.listenerType == LISTENER_HTTP:
                    igText(($listener.port).cstring)
                else:
                    igText("-")
            if igTableSetColumnIndex(5):
                if listener.listenerType == LISTENER_HTTP:
                    for host in listener.hosts.split(";"):
                        igText(host.cstring)
                elif listener.listenerType == LISTENER_SMB:
                    igText(listener.pipe.cstring)
            if igTableSetColumnIndex(6):
                let buttonWidth = (igGetContentRegionAvail().x - igGetStyle().ItemSpacing.x) / 2.0f
                
                # Profile preview button
                if listener.listenerType == LISTENER_HTTP:
                    if igButton(("View Profile##" & $int32(i)).cstring, vec2(buttonWidth, 0.0f)):
                        component.profilePreview.clear()
                        component.profilePreview.addItem(LOG_OUTPUT, listener.profile)
                        component.showProfilePreview = true
                else:
                    igDummy(vec2(buttonWidth, 0.0f))
                
                igSameLine(0.0f, -1.0f)
                
                # Stop button
                igPushStyleColor(ImGuiCol_Button.int32, CONSOLE_ERROR_HOVERED)
                igPushStyleColor(ImGuiCol_ButtonHovered.int32, CONSOLE_ERROR)
                igPushStyleColor(ImGuiCol_ButtonActive.int32, CONSOLE_ERROR)
                if igButton(("Stop Listener##" & $int32(i)).cstring, vec2(buttonWidth, 0.0f)):
                    cq.connection.sendStopListener(listener.listenerId)
                igPopStyleColor(3)

        igEndTable()