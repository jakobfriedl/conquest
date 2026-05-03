import strutils, sequtils, times, tables, algorithm
import imguin/[cimgui, glfw_opengl, simple]
import ../../utils/[appImGui, globals]
import ../../../types/[common, client, event]
import ../../core/websocket

proc LootCredentials*(title: string, showComponent: ptr bool): CredentialsComponent =
    result = new CredentialsComponent
    result.title = title
    result.showComponent = showComponent
    result.items = initTable[string, LootItem]()

proc draw*(component: CredentialsComponent) =
    igBegin(component.title.cstring, component.showComponent, 0)
    defer: igEnd()

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

        for i, item in component.items.values().toSeq().sortedByIt(it.lootId):
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
                igText(item.agentId.cstring)
            if igTableSetColumnIndex(2):
                igText(item.host.cstring)
            if igTableSetColumnIndex(3):
                igText(($item.credType).cstring)
            if igTableSetColumnIndex(4):
                igText(item.username.cstring)
            if igTableSetColumnIndex(5):
                igText(item.value.cstring)
            if igTableSetColumnIndex(6):
                igText(item.timestamp.fromUnix().local().format("dd-MM-yyyy HH:mm:ss").cstring)
            if igTableSetColumnIndex(7):
                igText(item.note.cstring)

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