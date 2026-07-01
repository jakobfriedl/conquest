import strutils, sequtils, tables, times, algorithm
import imguin/[cimgui, glfw_opengl, simple]
import ./modals/[startListener, generatePayload]
import ./widgets/textarea
import ../utils/[appImGui, globals, utils]
import ../core/websocket
import ../../types/[common, client]

proc ListenersTable*(title: string, showComponent: ptr bool): ListenersTableComponent =
    result = new ListenersTableComponent
    result.title = title
    result.showComponent = showComponent
    result.listeners = initTable[string, UIListener]()
    result.selection = ImGuiSelectionBasicStorage_ImGuiSelectionBasicStorage()
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

    let listeners = component.listeners.values().toSeq().sortedByIt(it.timestamp)

    # Profile TOML Preview
    if component.showProfilePreview:
        igOpenPopup_str("Profile", ImGui_PopupFlags_None.int32)

    igSetNextWindowSize(vec2(700.0f, 800.0f), ImGuiCond_Always.int32)
    if igBeginPopupModal("Profile", addr component.showProfilePreview, ImGuiWindowFlags_NoResize.int32):
        component.profilePreview.draw(vec2(0.0f, 0.0f))
        igEndPopup()

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

    var pendingEdit = false
    let cols: int32 = 7
    if igBeginTable("Listeners", cols, tableFlags, vec2(0.0f, 0.0f), 0.0f):

        igTableSetupColumn("ListenerID", ImGuiTableColumnFlags_NoReorder.int32 or ImGuiTableColumnFlags_NoHide.int32, 0.0f, 0)
        igTableSetupColumn("Name", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Protocol", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Bind Address", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Bind Port", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Callback", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Creation Date", ImGuiTableColumnFlags_DefaultHide.int32, 0.0f, 0)

        igTableSetupScrollFreeze(0, 1)
        igTableHeadersRow()
        let tableBodyStartPos = igGetCursorScreenPos().y

        var multiSelectIO = igBeginMultiSelect(ImGuiMultiSelectFlags_ClearOnEscape.int32 or ImGuiMultiSelectFlags_BoxSelect1d.int32, component.selection[].Size, int32(listeners.len()))
        ImGuiSelectionBasicStorage_ApplyRequests(component.selection, multiSelectIO)

        for i, listener in listeners:
            igTableNextRow(ImGuiTableRowFlags_None.int32, 0.0f)

            if igTableSetColumnIndex(0):
                igSetNextItemSelectionUserData(i)
                var isSelected = ImGuiSelectionBasicStorage_Contains(component.selection, cast[ImGuiID](i))
                discard igSelectable_Bool(listener.listenerId.cstring, isSelected, ImGuiSelectableFlags_SpanAllColumns.int32, vec2(0.0f, 0.0f))
            if igTableSetColumnIndex(1):
                igTextWithTooltip(listener.name)
            if igTableSetColumnIndex(2):
                igTextWithTooltip(($listener.listenerType))
            if igTableSetColumnIndex(3):
                if listener.listenerType == LISTENER_HTTP:
                    igTextWithTooltip(listener.address)
                else:
                    igTextWithTooltip("-")
            if igTableSetColumnIndex(4):
                if listener.listenerType == LISTENER_HTTP:
                    igTextWithTooltip(($listener.port))
                else:
                    igTextWithTooltip("-")
            if igTableSetColumnIndex(5):
                if listener.listenerType == LISTENER_HTTP:
                    for host in listener.hosts.split(";"):
                        igTextWithTooltip(host)
                elif listener.listenerType == LISTENER_SMB:
                    igTextWithTooltip(listener.pipe)
            if igTableSetColumnIndex(6):
                igTextWithTooltip(listener.timestamp.fromUnix().local().format("dd-MM-yyyy HH:mm:ss"))            

        # Right-click context menu
        let showContextMenu =
            component.selection[].Size > 0 and
            igGetMousePos().y >= tableBodyStartPos and
            igBeginPopupContextWindow("ListenerContextMenu", ImGui_PopupFlags_MouseButtonRight.int32)

        if showContextMenu:
            let selectedListeners = listeners.filterIt(ImGuiSelectionBasicStorage_Contains(component.selection, cast[ImGuiID](listeners.find(it))))

            if igBeginMenu("Copy", true):
                for label in ["ListenerID", "Name", "Protocol", "Bind Address", "Bind Port", "Callback"]:
                    if igMenuItem(label.cstring, nil, false, true):
                        var toCopy = ""
                        for l in selectedListeners:
                            toCopy &= (case label:
                                of "ListenerID": l.listenerId
                                of "Name": l.name
                                of "Protocol": $l.listenerType
                                of "Bind Address": (if l.listenerType == LISTENER_HTTP: l.address else: "-")
                                of "Bind Port": (if l.listenerType == LISTENER_HTTP: $l.port else: "-")
                                of "Callback": (if l.listenerType == LISTENER_HTTP: l.hosts else: (if l.listenerType == LISTENER_SMB: l.pipe else: "-"))
                                else: "") & "\n"
                        igSetClipboardText(toCopy.strip().cstring)
                        igCloseCurrentPopup()
                igEndMenu()

            if igMenuItem("Edit", nil, false, selectedListeners.len() == 1):
                component.startListenerModal.setEdit(selectedListeners[0])
                pendingEdit = true
                igCloseCurrentPopup()

            if igMenuItem("View Profile", nil, false, selectedListeners.len() == 1 and selectedListeners[0].listenerType == LISTENER_HTTP):
                component.profilePreview.clear()
                component.profilePreview.addItem(LOG_OUTPUT, selectedListeners[0].profile)
                component.showProfilePreview = true
                ImGuiSelectionBasicStorage_Clear(component.selection)
                igCloseCurrentPopup()

            igSeparator()

            if igMenuItem("Stop Listener", nil, false, true):
                for l in selectedListeners:
                    cq.connection.sendStopListener(l.listenerId)
                ImGuiSelectionBasicStorage_Clear(component.selection)
                igCloseCurrentPopup()

            igEndPopup()

        multiSelectIO = igEndMultiSelect()
        ImGuiSelectionBasicStorage_ApplyRequests(component.selection, multiSelectIO)

        igEndTable()

    if pendingEdit:
        igOpenPopup_str("Edit Listener", ImGui_PopupFlags_None.int32)

    let listener = component.startListenerModal.draw()
    if listener != nil:
        cq.connection.sendStartListener(listener)

    let buildInformation = component.generatePayloadModal.draw(listeners)
    if buildInformation != nil:
        cq.connection.sendAgentBuild(buildInformation)