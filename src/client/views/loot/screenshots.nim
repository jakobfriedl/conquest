import strformat, strutils, times, os, tables, native_dialogs
import imguin/[cimgui, glfw_opengl, simple]
import ../../utils/[appImGui, colors]
import ../../../common/[types, utils]
import ../../core/websocket

type
    ScreenshotTexture* = ref object 
        textureId*: GLuint
        data*: string
        width: int 
        height: int 

    ScreenshotsComponent* = ref object of RootObj
        title: string
        items*: seq[LootItem]
        selectedIndex: int
        textures: Table[string, ScreenshotTexture]

proc LootScreenshots*(title: string): ScreenshotsComponent =
    result = new ScreenshotsComponent
    result.title = title
    result.items = @[]
    result.selectedIndex = -1
    result.textures = initTable[string, ScreenshotTexture]()

proc addTexture*(component: ScreenshotsComponent, lootId: string, data: string) = 
    var textureId: GLuint
    let (width, height) = loadTextureFromBytes(string.toBytes(data), textureId)
    component.textures[lootId] = ScreenshotTexture(
        textureId: textureId,
        data: data,
        width: width, 
        height: height
    )

proc draw*(component: ScreenshotsComponent, showComponent: ptr bool, connection: WsConnection) =
    igBegin(component.title, showComponent, 0)
    defer: igEnd()

    var availableSize: ImVec2
    igGetContentRegionAvail(addr availableSize)
    let textSpacing = igGetStyle().ItemSpacing.x    
        
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
        
        let cols: int32 = 5
        if igBeginTable("##Items", cols, tableFlags, vec2(0.0f, 0.0f), 0.0f):
            igTableSetupColumn("ID", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
            igTableSetupColumn("AgentID", ImGuiTableColumnFlags_DefaultHide.int32, 0.0f, 0)
            igTableSetupColumn("Host", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
            igTableSetupColumn("Creation Date", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
            igTableSetupColumn("File Size", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
            igTableSetupScrollFreeze(0, 1)
            igTableHeadersRow()
        
            for i, item in component.items:
                igTableNextRow(ImGuiTableRowFlags_None.int32, 0.0f)
                
                if igTableSetColumnIndex(0):
                    igPushID_Int(i.int32)
                    let isSelected = component.selectedIndex == i
                    if igSelectable_Bool(item.lootId.cstring, isSelected, ImGuiSelectableFlags_SpanAllColumns.int32 or ImGuiSelectableFlags_AllowOverlap.int32, vec2(0, 0)):
                        component.selectedIndex = i
                
                    if igIsItemHovered(ImGuiHoveredFlags_None.int32) and igIsMouseClicked_Bool(ImGuiMouseButton_Right.int32, false):
                        component.selectedIndex = i
                    
                    igPopID()                

                if igTableSetColumnIndex(1):
                    igText(item.agentId)

                if igTableSetColumnIndex(2):
                    igText(item.host.cstring)

                if igTableSetColumnIndex(3):
                    igText(item.timestamp.fromUnix().local().format("dd-MM-yyyy HH:mm:ss"))

                if igTableSetColumnIndex(4):
                    igText($item.size)

            # Handle right-click context menu
            if component.selectedIndex >= 0 and component.selectedIndex < component.items.len and igBeginPopupContextWindow("Downloads", ImGui_PopupFlags_MouseButtonRight.int32): 
                
                let item = component.items[component.selectedIndex]

                if igMenuItem("Download", nil, false, true):                     
                    # Download screenshot 
                    try: 
                        let path = callDialogFileSave("Save File") 
                        let data = component.textures[item.lootId].data
                        writeFile(path, data)
                    except IOError: 
                        discard 
                    igCloseCurrentPopup()

                if igMenuItem("Remove", nil, false, true): 
                    # Task team server to remove the loot item 
                    connection.sendRemoveLoot(item.lootId)
                    component.items.delete(component.selectedIndex)
                    igCloseCurrentPopup()

                igEndPopup()

            igEndTable()
        
    igEndChild()
    igSameLine(0.0f, 0.0f)
    
    # Right panel (file content)
    if igBeginChild_Str("##Preview", vec2(0.0f, 0.0f), ImGui_ChildFlags_Borders.int32, ImGui_WindowFlags_None.int32):

        if component.selectedIndex >= 0 and component.selectedIndex < component.items.len:

            let item = component.items[component.selectedIndex]
            
            # Check if the texture for the loot item has already been loaded from the team server
            # If the texture doesn't exist yet, send a request to the team server to retrieve and render it
            if not component.textures.hasKey(item.lootId): 
                connection.sendGetLoot(item.lootId)     
                component.textures[item.lootId] = nil       # Ensure that the sendGetLoot() function is sent only once by setting a value for the table key

            # Display the image preview
            else: 
                let texture = component.textures[item.lootId]
                if not texture.isNil(): 
                    igImage(ImTextureRef(internal_TexData: nil, internal_TexID: texture.textureId), vec2(texture.width, texture.height), vec2(0, 0), vec2(1, 1))

        else:
            igText("Select item for preview.")
    igEndChild()