import times, tables, sequtils, algorithm, os
import imguin/[cimgui, glfw_opengl, simple]
import ../../../common/utils
import ../../../types/[client, event]
import ../../utils/[appImGui, globals, dialogs]
import ../../core/websocket

proc LootScreenshots*(title: string, showComponent: ptr bool): ScreenshotsComponent =
    result = new ScreenshotsComponent
    result.title = title
    result.showComponent = showComponent
    result.items = initTable[string, tuple[item: LootItem, texture: ScreenshotTexture]]()

proc addTexture*(component: ScreenshotsComponent, lootId: string, data: string) = 
    var textureId: GLuint
    let (width, height) = loadTextureFromBytes(string.toBytes(data), textureId)
    component.items[lootId].texture = ScreenshotTexture(
        textureId: textureId,
        data: data,
        width: width, 
        height: height
    )

proc draw*(component: ScreenshotsComponent) =
    igBegin(component.title.cstring, component.showComponent, 0)
    defer: igEnd()

    var availableSize = igGetContentRegionAvail()
        
    # Left panel (file table) 
    let childFlags = ImGui_ChildFlags_ResizeX.int32 or ImGui_ChildFlags_NavFlattened.int32
    if igBeginChild_Str("##Left", vec2(availableSize.x * 0.5f, 0.0f), childFlags, ImGui_WindowFlags_None.int32):

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
        
        let cols: int32 = 7
        if igBeginTable("##Items", cols, tableFlags, vec2(0.0f, 0.0f), 0.0f):
            igTableSetupColumn("ID", ImGuiTableColumnFlags_NoHide.int32, 0.0f, 0)
            igTableSetupColumn("AgentID", ImGuiTableColumnFlags_DefaultHide.int32, 0.0f, 0)
            igTableSetupColumn("Host", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
            igTableSetupColumn("Path", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
            igTableSetupColumn("Size", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
            igTableSetupColumn("Creation Date", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
            igTableSetupColumn("Note", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
            igTableSetupScrollFreeze(0, 1)
            igTableHeadersRow()

            for i, entry in component.items.values().toSeq().sortedByIt(it.item.timestamp):
                let item = entry.item
                igTableNextRow(ImGuiTableRowFlags_None.int32, 0.0f)

                if igTableSetColumnIndex(0):
                    igPushID_Int(i.int32)
                    let isSelected = component.selectedLootId == item.lootId
                    if igSelectable_Bool(item.lootId.cstring, isSelected, ImGuiSelectableFlags_SpanAllColumns.int32 or ImGuiSelectableFlags_AllowOverlap.int32, vec2(0, 0)):
                        component.selectedLootId = item.lootId

                    if igIsItemHovered(ImGuiHoveredFlags_None.int32) and igIsMouseClicked_Bool(ImGuiMouseButton_Right.int32, false):
                        component.selectedLootId = item.lootId

                    igPopID()

                if igTableSetColumnIndex(2):
                    igTextWithTooltip(item.agentId)
                if igTableSetColumnIndex(1):
                    igTextWithTooltip(item.host)
                if igTableSetColumnIndex(3):
                    igTextWithTooltip(item.path.extractFilename())
                if igTableSetColumnIndex(4):
                    igTextWithTooltip($item.size)
                if igTableSetColumnIndex(5):
                    igTextWithTooltip(item.timestamp.fromUnix().local().format("dd-MM-yyyy HH:mm:ss"))
                if igTableSetColumnIndex(6):
                    igTextWithTooltip(item.note)

            # Handle right-click context menu
            if component.selectedLootId != "" and component.items.hasKey(component.selectedLootId) and igBeginPopupContextWindow("Downloads", ImGui_PopupFlags_MouseButtonRight.int32): 
                let item = component.items[component.selectedLootId].item

                if igBeginMenu("Copy", true):
                    if igMenuItem("Local Path", nil, false, true):
                        igSetClipboardText(item.path.cstring)
                        igCloseCurrentPopup()
                    if igMenuItem("Note", nil, false, true):
                        igSetClipboardText(item.note.cstring)
                        igCloseCurrentPopup()
                    igEndMenu()

                if igMenuItem("Download", nil, false, true):                     
                    try: 
                        let path = callDialogFileSave("Save File", item.path.extractFilename())                     
                        let data = component.items[component.selectedLootId].texture.data
                        writeFile(path, data)
                    except IOError: 
                        discard 
                    igCloseCurrentPopup()

                if igMenuItem("Remove", nil, false, true): 
                    cq.connection.sendRemoveLoot(item.lootId)
                    component.items.del(item.lootId)
                    component.selectedLootId = ""
                    igCloseCurrentPopup()

                igEndPopup()

            igEndTable()
        
    igEndChild()
    igSameLine(0.0f, 0.0f)
    
    if igIsKeyPressed_Bool(ImGui_Key_Escape, false):
        component.selectedLootId = ""

    # Right panel (image preview)
    if igBeginChild_Str("##Preview", vec2(0.0f, 0.0f), ImGui_ChildFlags_Borders.int32, ImGui_WindowFlags_None.int32):

        if component.selectedLootId != "" and component.items.hasKey(component.selectedLootId):
            let entry = component.items[component.selectedLootId]

            # Check if the texture has already been loaded from the team server
            # If the texture doesn't exist yet, send a request to the team server to retrieve and render it
            if entry.texture.isNil():
                cq.connection.sendGetLoot(component.selectedLootId)
                component.items[component.selectedLootId].texture = ScreenshotTexture() # Ensure that the sendGetLoot() function is sent only once by setting a value for the table key

            else:
                let texture = entry.texture
                if texture.textureId != 0:
                    igImage(ImTextureRef(internal_TexData: nil, internal_TexID: texture.textureId), vec2(texture.width, texture.height), vec2(0, 0), vec2(1, 1))

        else:
            igText("Select item for preview.")

    igEndChild()