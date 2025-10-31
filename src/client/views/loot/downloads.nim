import strformat, strutils, times, os, tables, native_dialogs
import imguin/[cimgui, glfw_opengl, simple]
import ../../utils/appImGui
import ../../../common/types
import ../../core/websocket
import ../widgets/textarea

type
    DownloadsComponent* = ref object of RootObj
        title: string
        items*: seq[LootItem]
        contents*: Table[string, string]
        textarea: TextareaWidget
        selectedIndex: int
        

proc LootDownloads*(title: string): DownloadsComponent =
    result = new DownloadsComponent
    result.title = title
    result.items = @[]
    result.contents = initTable[string, string]() 
    result.selectedIndex = -1
    result.textarea = Textarea(showTimestamps = false, autoScroll = false)

proc draw*(component: DownloadsComponent, showComponent: ptr bool, connection: WsConnection) =
    igBegin(component.title.cstring, showComponent, 0)
    defer: igEnd()

    var availableSize: ImVec2
    igGetContentRegionAvail(addr availableSize)
        
    # Left panel (file table) 
    let childFlags = ImGui_ChildFlags_ResizeX.int32 or ImGui_ChildFlags_NavFlattened.int32
    if igBeginChild_Str("##Left", vec2(availableSize.x * 0.66f, 0.0f), childFlags, ImGui_WindowFlags_None.int32):

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
        
        let cols: int32 = 6
        if igBeginTable("##Items", cols, tableFlags, vec2(0.0f, 0.0f), 0.0f):
            igTableSetupColumn("ID", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
            igTableSetupColumn("AgentID", ImGuiTableColumnFlags_DefaultHide.int32, 0.0f, 0)
            igTableSetupColumn("Host", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
            igTableSetupColumn("Path", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
            igTableSetupColumn("Creation Date", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
            igTableSetupColumn("Size", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
            igTableSetupScrollFreeze(0, 1)
            igTableHeadersRow()
        
            for i, item in component.items:
                igTableNextRow(ImGuiTableRowFlags_None.int32, 0.0f)
                
                if igTableSetColumnIndex(0):
                    igPushID_Int(i.int32)
                    let isSelected = component.selectedIndex == i
                    if igSelectable_Bool(item.lootId.cstring, isSelected, ImGuiSelectableFlags_SpanAllColumns.int32 or ImGuiSelectableFlags_AllowOverlap.int32, vec2(0, 0)):
                        component.selectedIndex = i
                        component.textarea.clear()
                    
                    if igIsItemHovered(ImGuiHoveredFlags_None.int32) and igIsMouseClicked_Bool(ImGuiMouseButton_Right.int32, false):
                        component.selectedIndex = i
                    
                    igPopID()

                if igTableSetColumnIndex(1):
                    igText(item.agentId.cstring)

                if igTableSetColumnIndex(2):
                    igText(item.host.cstring)
                
                if igTableSetColumnIndex(3):
                    igText(item.path.extractFilename().replace("C_", "C:/").replace("_", "/").cstring)

                if igTableSetColumnIndex(4):
                    igText(item.timestamp.fromUnix().local().format("dd-MM-yyyy HH:mm:ss").cstring)

                if igTableSetColumnIndex(5):
                    igText(($item.size).cstring)
                                        
            # Handle right-click context menu
            if component.selectedIndex >= 0 and component.selectedIndex < component.items.len and igBeginPopupContextWindow("Downloads", ImGui_PopupFlags_MouseButtonRight.int32): 
                let item = component.items[component.selectedIndex]

                if igMenuItem("Download", nil, false, true):                     
                    # Download file
                    try: 
                        let path = callDialogFileSave("Save File")                     
                        let data = component.contents[item.lootId]
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
            
            if not component.contents.hasKey(item.lootId): 
                connection.sendGetLoot(item.lootId)     
                component.contents[item.lootId] = ""       # Ensure that the sendGetLoot() function is sent only once by setting a value for the table key

            else: 
                igText(fmt"[{item.host}] ".cstring)
                igSameLine(0.0f, 0.0f)
                igText(item.path.extractFilename().replace("C_", "C:/").replace("_", "/").cstring)
                
                igDummy(vec2(0.0f, 5.0f))
                igSeparator()
                igDummy(vec2(0.0f, 5.0f)) 

                if component.textarea.isEmpty() and not component.contents[item.lootId].isEmptyOrWhitespace():
                    component.textarea.addItem(LOG_OUTPUT, component.contents[item.lootId])
                
                component.textarea.draw(vec2(-1.0f, -1.0f))
            
        else:
            igText("Select item to preview contents")

    igEndChild()