import strformat, strutils, times
import imguin/[cimgui, glfw_opengl, simple]
import ../../utils/[appImGui, colors]
import ../../../common/[types, utils]

type
    DownloadsComponent* = ref object of RootObj
        title: string
        items: seq[LootItem]
        selectedIndex: int
        

proc LootDownloads*(title: string): DownloadsComponent =
    result = new DownloadsComponent
    result.title = title
    result.items = @[]
    result.selectedIndex = -1

    result.items.add(@[LootItem(
        agentId: "DEADBEEF",
        path: "C:\\Software\\Conquest\\README.md", 
        timestamp: now().toTime().toUnix(),
        size: 1000, 
        host: "WKS-1", 
        data: string.toBytes("README.md\nPreview\nHello world.")
    ),
    LootItem(
        agentId: "DEADBEEF",
        path: "C:\\Software\\Conquest\\README.md", 
        timestamp: now().toTime().toUnix(),
        size: 1000, 
        host: "WKS-1", 
        data: string.toBytes("README.md\nPreview\nHello world.")
    )
    ])

proc draw*(component: DownloadsComponent, showComponent: ptr bool) =
    igBegin(component.title, showComponent, 0)
    defer: igEnd()

    var availableSize: ImVec2
    igGetContentRegionAvail(addr availableSize)
    let textSpacing = igGetStyle().ItemSpacing.x    
        
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
        
        let cols: int32 = 4
        if igBeginTable("##Items", cols, tableFlags, vec2(0.0f, 0.0f), 0.0f):
            igTableSetupColumn("Path", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
            igTableSetupColumn("Creation Date", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
            igTableSetupColumn("Size", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
            igTableSetupColumn("Host", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
            igTableSetupScrollFreeze(0, 1)
            igTableHeadersRow()
        
            for i, item in component.items:
                igTableNextRow(ImGuiTableRowFlags_None.int32, 0.0f)
                
                if igTableSetColumnIndex(0):
                    igPushID_Int(i.int32)
                    let isSelected = component.selectedIndex == i
                    if igSelectable_Bool(item.path.cstring, isSelected, ImGuiSelectableFlags_SpanAllColumns.int32 or ImGuiSelectableFlags_AllowOverlap.int32, vec2(0, 0)):
                        component.selectedIndex = i
                    igPopID()                

                if igTableSetColumnIndex(1):
                    igText(item.timestamp.fromUnix().local().format("dd-MM-yyyy HH:mm:ss"))

                if igTableSetColumnIndex(2):
                    igText($item.size)
                                        
                if igTableSetColumnIndex(3):
                    igText(item.host.cstring)

            igEndTable()
        
    igEndChild()
    igSameLine(0.0f, 0.0f)
    
    # Right panel (file content)
    if igBeginChild_Str("##Preview", vec2(0.0f, 0.0f), ImGui_ChildFlags_Borders.int32, ImGui_WindowFlags_None.int32):

        if component.selectedIndex >= 0 and component.selectedIndex < component.items.len:
            let item = component.items[component.selectedIndex]
            
            igText(item.path)
            
        else:
            igText("Select item to preview contents")
    igEndChild()