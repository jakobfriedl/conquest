import imguin/[cimgui, glfw_opengl]
import sequtils, strutils, strformat, tables, times, algorithm, options, std/paths
import ../utils/[appImGui, globals]
import ../core/[task, websocket]
import ./moduleManager
import ../../types/[common, client]

proc FileBrowser*(title: string, showComponent: ptr bool): FileBrowserComponent = 
    result = new FileBrowserComponent
    result.title = title
    result.showComponent = showComponent
    result.agent = 0
    result.selection = "" 

proc formatFileSize(size: int): string =
    if size == 0:
        return "0B"
    elif size < 1024:
        return fmt"{size}B"
    elif size < 1024 * 1024:
        return fmt"{size / 1024:.2f}KB"
    elif size < 1024 * 1024 * 1024:
        return fmt"{size / (1024 * 1024):.2f}MB"
    else:
        return fmt"{size / (1024 * 1024 * 1024):.2f}GB"

proc formatFlags(flags: uint8): string =
    # Compact professional format: [d]ir, [a]rchive, [r]eadonly, [h]idden, [s]ystem
    result = "-----"
    if (flags and cast[uint8](IS_DIR)) != 0:      result[0] = 'd'
    if (flags and cast[uint8](IS_ARCHIVE)) != 0:  result[1] = 'a'
    if (flags and cast[uint8](IS_READONLY)) != 0: result[2] = 'r'
    if (flags and cast[uint8](IS_HIDDEN)) != 0:   result[3] = 'h'
    if (flags and cast[uint8](IS_SYSTEM)) != 0:   result[4] = 's'

proc draw*(component: FileBrowserComponent) = 
    igBegin(component.title.cstring, component.showComponent, 0)
    defer: igEnd() 

    let textSpacing = igGetStyle().ItemSpacing.x  

    # Retrieve agent list 
    let agents = cq.sessions.agents.values().toSeq().sortedByIt(it.firstCheckin)

    # Dropdown menu to select the agent
    igSetNextItemWidth(200.0f)  
    igCombo_Str("##SelectAgent", addr component.agent, ("[Select Agent]\0" & agents.mapIt(it.agentId).join("\0") & "\0").cstring , agents.len().int32 + 1)
    igSameLine(0.0f, textSpacing)
    
    if component.agent > agents.len():
        component.agent = 0
    if component.agent == 0: return

    let agent = agents[component.agent - 1]

    # Buttons 
    igSameLine(0.0f, textSpacing)
    if igButton("List drives", vec2(0.0f, 0.0f)):
        # TODO: Implement command to list drives
        discard 

    igSameLine(0.0f, textSpacing)
    if igButton("List working directory", vec2(0.0f, 0.0f)):
        sendTask(agent.agentId, "ls", silent = true)

    igSameLine(0.0f, textSpacing)
    let workingDirectory = agent.workingDirectory.get("-")
    igText(fmt"Current: {workingDirectory}".cstring)

    igDummy(vec2(0.0f, 2.5f))
    igSeparator() 
    igDummy(vec2(0.0f, 2.5f))

    # Filesystem tree view
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
    let treeFlags = (
        ImGuiTreeNodeFlags_DrawLinesToNodes.int32 or 
        ImGuiTreeNodeFlags_DefaultOpen.int32 or 
        ImGuiTreeNodeFlags_OpenOnDoubleClick.int32 or 
        ImGuiTreeNodeFlags_OpenOnArrow.int32
    )

    let cols: int32 = 4
    if igBeginTable("Filesystem", cols, tableFlags, vec2(0.0f, 0.0f), 0.0f):
        
        igTableSetupColumn("Name", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Flags", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Size", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Last modified", ImGuiTableColumnFlags_None.int32, 0.0f, 0)

        igTableSetupScrollFreeze(0, 1)
        igTableHeadersRow()
        
        if agent.filesystem.isSome():
            let fs = agent.filesystem.get()

            proc printDirectoryEntry(entry: DirectoryEntry, path: string) =
                igTableNextRow(ImGuiTableRowFlags_None.int32, 0.0f)
                
                let isSelected = component.selection == path
                let hasChildren = entry.children.isSome() and entry.children.get().len > 0
                let isDir = (entry.flags and cast[uint8](IS_DIR)) != 0
                
                if igTableSetColumnIndex(0):
                    let flags = if hasChildren: treeFlags else: ImGuiTreeNodeFlags_Leaf.int32
                    let nodeId = fmt"##{entry.name}_{entry.lastWriteTime}"
                    let open = igTreeNodeEx_Str(nodeId.cstring, flags)
                    
                    igSameLine(0.0f, textSpacing)                    
                    
                    var name = ""

                    # Grey out unloaded directories and add icons for better readability
                    if isDir and not entry.isLoaded: 
                        igPushStyleColor_Vec4(ImGuiCol_Text.int32, GRAY)
                        name = ICON_FA_FOLDER_CLOSED & " " & entry.name
                    elif isDir and entry.isLoaded:
                        name = ICON_FA_FOLDER_OPEN & " " & entry.name
                    else: 
                        name = ICON_FA_FILE & " " & entry.name

                    # Check if the directory is a drive
                    if isDir and entry.name.len() == 2 and entry.name.endsWith(":"):
                        name = ICON_FA_HARD_DRIVE & " " & entry.name & "/"

                    # Check if directory is a remote system
                    if isDir and entry.name.startsWith("\\\\"):
                        name = ICON_FA_SERVER & " " & entry.name

                    if igSelectable_Bool(name.cstring, isSelected, ImGuiSelectableFlags_SpanAllColumns.int32, vec2(0.0f, 0.0f)):
                        component.selection = path
                   
                    if isDir and not entry.isLoaded: 
                        igPopStyleColor(1)
                    
                    # Right-click context menu
                    if igBeginPopupContextItem(fmt"##ContextMenu".cstring, ImGuiPopupFlags_MouseButtonRight.int32):
                        # If the selected item is a directory, provide the option to cd to it, 
                        # If not, make the selected file downloadable
                        if isDir:
                            if igMenuItem_Bool(fmt"Change current working directory to {path}/".cstring, nil, false, true):
                                sendTask(agent.agentId, "cd \"" & path & "/\"", silent = true)
                                igCloseCurrentPopup()
                        else:
                            if igMenuItem_Bool(fmt"Download {path}".cstring, nil, false, true):
                                sendTask(agent.agentId, "download \"" & path & "\"", silent = true)
                                igCloseCurrentPopup()
                        
                        igEndPopup()
                    
                    # Double-click to load directory contents
                    if igIsItemHovered(0) and igIsMouseDoubleClicked_Nil(ImGuiMouseButton_Left.int32):
                        if isDir and not entry.isLoaded:
                            sendTask(agent.agentId, "ls \"" & path & "/\"", silent = true)
                    
                    # Flags
                    if igTableSetColumnIndex(1):
                        igText(formatFlags(entry.flags).cstring)
                    
                    # Size
                    if igTableSetColumnIndex(2):
                        if not isDir:
                            igText(formatFileSize(int(entry.size)).cstring)
                        else:
                            igTextDisabled("-")
                    
                    # Last modified timestamp
                    if igTableSetColumnIndex(3):
                        if entry.lastWriteTime > 0:
                            let dt = entry.lastWriteTime.fromUnix().local()
                            igText(dt.format("dd/MM/yyyy HH:mm:ss").cstring)
                        else:
                            igTextDisabled("-")
                    
                    if open:
                        if hasChildren:
                            for childName, childEntry in entry.children.get().pairs:
                                printDirectoryEntry(childEntry, $(cast[Path](path) / cast[Path](childName)))
                        igTreePop()

            for name, entry in fs.pairs:
                printDirectoryEntry(entry, name)
        
        igEndTable()