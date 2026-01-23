import imguin/[cimgui, glfw_opengl]
import sequtils, strutils, strformat, tables, times, algorithm, options
import ../utils/[appImGui, globals]
import ../core/[task, websocket, context]
import ./moduleManager
import ../../common/types

#     ProcessBrowserComponent* = ref object of RootObj
#         title: string 
#         agent: int32
#         selection*: uint32

proc ProcessBrowser*(title: string, showComponent: ptr bool): ProcessBrowserComponent = 
    result = new ProcessBrowserComponent
    result.title = title
    result.showComponent = showComponent
    result.agent = 0
    result.selection = 0 

proc draw*(component: ProcessBrowserComponent) = 
    igBegin(component.title.cstring, component.showComponent, 0)
    defer: igEnd() 

    let textSpacing = igGetStyle().ItemSpacing.x  

    # Retrieve agent list 
    let agents = cq.sessions.agents.values().toSeq().sorted(cmp) 

    # Dropdown menu to select the agent
    igSetNextItemWidth(200.0f)  
    igCombo_Str("##SelectAgent", addr component.agent, ("[Select Agent]\0" & agents.mapIt(it.agentId).join("\0") & "\0").cstring , agents.len().int32 + 1)
    igSameLine(0.0f, textSpacing)
    
    if component.agent > agents.len():
        component.agent = 0
    if component.agent == 0: return

    let agent = agents[component.agent - 1]
    if igButton(ICON_FA_ROTATE_RIGHT, vec2(0.0f, 0.0f)):
        sendTask(agent.agentId, "ps")

    var latestUpdate: string = "Never"
    if cq.sessions.agents[agent.agentId].processes.isSome():
        let duration = now() - cq.sessions.agents[agent.agentId].processes.get().timestamp.fromUnix().local()
        let totalSeconds = duration.inSeconds
                    
        let hours = totalSeconds div 3600
        let minutes = (totalSeconds mod 3600) div 60
        let seconds = totalSeconds mod 60
        latestUpdate = fmt"{hours:02d}:{minutes:02d}:{seconds:02d} ago"
    igSameLine(0.0f, textSpacing)
    igText(fmt"Latest update: {latestUpdate}".cstring)

    igDummy(vec2(0.0f, 2.5f))
    igSeparator() 
    igDummy(vec2(0.0f, 2.5f))

    # Process tree view
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

    let cols: int32 = 5
    if igBeginTable("Processes", cols, tableFlags, vec2(0.0f, 0.0f), 0.0f):
        
        igTableSetupColumn("Process name", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("PID", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("PPID", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Session", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("User context", ImGuiTableColumnFlags_None.int32, 0.0f, 0)

        igTableSetupScrollFreeze(0, 1)
        igTableHeadersRow()

        if agent.processes.isSome():
            let processes = agent.processes.get()

            proc printProcess(pid: uint32) = 
                if not processes.processTable.contains(pid) or pid == 0:
                    return

                igTableNextRow(ImGuiTableRowFlags_None.int32, 0.0f)
                
                let process = processes.processTable[pid]
                let isSelected = component.selection == pid
                
                if igTableSetColumnIndex(0):
                    let flags = if process.children.len() > 0: treeFlags else: ImGuiTreeNodeFlags_Leaf.int32
                    let open = igTreeNodeEx_Str(fmt"##{pid}".cstring, flags)
                    
                    igSameLine(0.0f, textSpacing)

                    # Highlight agent process
                    if int(pid) == agent.pid:
                        igPushStyleColor_Vec4(ImGuiCol_Text.int32, CONSOLE_HIGHLIGHT)
                
                    if igSelectable_Bool(process.name.cstring, isSelected, ImGuiSelectableFlags_SpanAllColumns.int32, vec2(0.0f, 0.0f)):
                        component.selection = pid
                    
                    if igTableSetColumnIndex(1):
                        igText(($process.pid).cstring) 
                    if igTableSetColumnIndex(2): 
                        igText(($process.ppid).cstring)
                    if igTableSetColumnIndex(3):
                        igText(($process.session).cstring) 
                    if igTableSetColumnIndex(4): 
                        igText(process.user.cstring)
                    
                    # Remove color highlighting
                    if int(pid) == agent.pid: 
                        igPopStyleColor(1)

                    if open:
                        if process.children.len() > 0:
                            for childPid in process.children.sorted():
                                printProcess(childPid)
                        igTreePop()

            for pid in processes.rootProcesses:
                printProcess(pid)

        igEndTable()