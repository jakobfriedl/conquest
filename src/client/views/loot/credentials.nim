import sequtils, times, tables, algorithm
import imguin/[cimgui, glfw_opengl, simple]
import ../../utils/[appImGui, globals]
import ../../../types/[client, event]
import ../modals/addCredential
import ../../core/websocket

proc LootCredentials*(title: string, showComponent: ptr bool): CredentialsComponent =
    result = new CredentialsComponent
    result.title = title
    result.showComponent = showComponent
    result.items = initTable[string, LootItem]()
    result.credentialModal = CredentialModal() 

proc draw*(component: CredentialsComponent) =
    igBegin(component.title.cstring, component.showComponent, 0)
    defer: igEnd()

    # Modal for adding credentials manually 
    if igButton("Add Credential", vec2(0.0f, 0.0f)):
        igOpenPopup_str("Add Credential", ImGui_PopupFlags_None.int32)
    component.credentialModal.draw()

    let tableFlags = (
        ImGui_TableFlags_Resizable.int32 or
        ImGui_TableFlags_Reorderable.int32 or
        ImGui_TableFlags_Hideable.int32 or
        ImGui_TableFlags_HighlightHoveredColumn.int32 or
        ImGui_TableFlags_RowBg.int32 or
        ImGui_TableFlags_BordersV.int32 or
        ImGui_TableFlags_BordersH.int32 or
        ImGui_TableFlags_ScrollY.int32 or
        ImGui_TableFlags_ScrollX.int32 or
        ImGui_TableFlags_NoBordersInBodyUntilResize.int32 or
        ImGui_TableFlags_SizingStretchSame.int32
    )

    let cols: int32 = 8
    if igBeginTable("##Credentials", cols, tableFlags, vec2(0.0f, 0.0f), 0.0f):
        igTableSetupColumn("ID", ImGuiTableColumnFlags_NoHide.int32, 0.0f, 0)
        igTableSetupColumn("AgentID", ImGuiTableColumnFlags_DefaultHide.int32, 0.0f, 0)
        igTableSetupColumn("Host", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Credential Type", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Username", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Value", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Creation Date", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Note", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupScrollFreeze(0, 1)
        igTableHeadersRow()

        for i, item in component.items.values().toSeq().sortedByIt(it.timestamp):
            igTableNextRow(ImGuiTableRowFlags_None.int32, 0.0f)

            if igTableSetColumnIndex(0):
                igPushID_Int(i.int32)
                let isSelected = component.selectedLootId == item.lootId
                if igSelectable_Bool(item.lootId.cstring, isSelected, ImGuiSelectableFlags_SpanAllColumns.int32 or ImGuiSelectableFlags_AllowOverlap.int32, vec2(0, 0)):
                    component.selectedLootId = item.lootId

                if igIsItemHovered(ImGuiHoveredFlags_None.int32) and igIsMouseClicked_Bool(ImGuiMouseButton_Right.int32, false):
                    component.selectedLootId = item.lootId

                igPopID()

            if igTableSetColumnIndex(1):
                igTextWithTooltip(item.agentId)
            if igTableSetColumnIndex(2):
                igTextWithTooltip(item.host)
            if igTableSetColumnIndex(3):
                igTextWithTooltip($item.credType)
            if igTableSetColumnIndex(4):
                igTextWithTooltip(item.username)
            if igTableSetColumnIndex(5):
                igTextWithTooltip(item.value)
            if igTableSetColumnIndex(6):
                igTextWithTooltip(item.timestamp.fromUnix().local().format("dd-MM-yyyy HH:mm:ss"))
            if igTableSetColumnIndex(7):
                igTextWithTooltip(item.note)

        # Handle right-click context menu
        if component.selectedLootId != "" and component.items.hasKey(component.selectedLootId) and igBeginPopupContextWindow("Credentials", ImGui_PopupFlags_MouseButtonRight.int32):
            let item = component.items[component.selectedLootId]

            if igBeginMenu("Copy", true):
                if igMenuItem("Username", nil, false, true):
                    igSetClipboardText(item.username.cstring)
                    igCloseCurrentPopup()
                if igMenuItem("Value", nil, false, true):
                    igSetClipboardText(item.value.cstring)
                    igCloseCurrentPopup()
                if igMenuItem("Username:Value", nil, false, true):
                    igSetClipboardText((item.username & ":" & item.value).cstring)
                    igCloseCurrentPopup()
                if igMenuItem("Note", nil, false, true):
                    igSetClipboardText(item.note.cstring)
                    igCloseCurrentPopup()
                igEndMenu()

            if igMenuItem("Remove", nil, false, true):
                cq.connection.sendRemoveLoot(item.lootId)
                component.items.del(item.lootId)
                component.selectedLootId = ""
                igCloseCurrentPopup()

            igEndPopup()

        if igIsKeyPressed_Bool(ImGui_Key_Escape, false):
            component.selectedLootId = ""

        igEndTable()