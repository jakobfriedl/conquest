import times, tables, strformat, strutils, algorithm
import imguin/[cimgui, glfw_opengl, simple]

import ./console
import ../core/[task, websocket]
import ../utils/[appImGui, colors]
import ../../modules/manager
import ../../common/[types, utils]

type 
    SessionsTableComponent* = ref object of RootObj
        title: string 
        agents*: seq[UIAgent]
        agentActivity*: Table[string, int64]                # Direct O(1) access to latest checkin
        agentImpersonation*: Table[string, string]
        selection: ptr ImGuiSelectionBasicStorage
        consoles: ptr Table[string, ConsoleComponent]

proc SessionsTable*(title: string, consoles: ptr Table[string, ConsoleComponent]): SessionsTableComponent = 
    result = new SessionsTableComponent
    result.title = title
    result.agents = @[]
    result.agentActivity = initTable[string, int64]()
    result.selection = ImGuiSelectionBasicStorage_ImGuiSelectionBasicStorage()
    result.consoles = consoles

proc cmp(x, y: UIAgent): int =
    return cmp(x.firstCheckin, y.firstCheckin)

proc interact(component: SessionsTableComponent) = 
    # Open a new console for each selected agent session
    var it: pointer = nil
    var row: ImGuiID

    while ImGuiSelectionBasicStorage_GetNextSelectedItem(component.selection, addr it, addr row):
        let agent = component.agents[cast[int](row)]

        # Create a new console window
        if not component.consoles[].hasKey(agent.agentId):
            component.consoles[][agent.agentId] = Console(agent)

        # Focus the existing console window
        else:
            igSetWindowFocus_Str(fmt"[{agent.agentId}] {agent.username}@{agent.hostname}")
    
    component.selection.ImGuiSelectionBasicStorage_Clear()

proc draw*(component: SessionsTableComponent, showComponent: ptr bool, connection: WsConnection) = 
    igBegin(component.title, showComponent, 0)

    let textSpacing = igGetStyle().ItemSpacing.x

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

    let cols: int32 = 12
    if igBeginTable("Sessions", cols, tableFlags, vec2(0.0f, 0.0f), 0.0f):

        igTableSetupColumn("AgentID", ImGuiTableColumnFlags_NoReorder.int32 or ImGuiTableColumnFlags_NoHide.int32, 0.0f, 0)
        igTableSetupColumn("ListenerID", ImGuiTableColumnFlags_DefaultHide.int32, 0.0f, 0)
        igTableSetupColumn("IP (Internal)", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("IP (External)", ImGuiTableColumnFlags_DefaultHide.int32, 0.0f, 0)
        igTableSetupColumn("Username", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Hostname", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Domain", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("OS", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Process", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("PID", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("First seen", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Last seen", ImGuiTableColumnFlags_None.int32, 0.0f, 0)

        igTableSetupScrollFreeze(0, 1)
        igTableHeadersRow()
        
        var multiSelectIO = igBeginMultiSelect(ImGuiMultiSelectFlags_ClearOnEscape.int32 or ImGuiMultiSelectFlags_BoxSelect1d.int32, component.selection[].Size, int32(component.agents.len())) 
        ImGuiSelectionBasicStorage_ApplyRequests(component.selection, multiSelectIO)

        # Sort sessions table based on first checkin
        component.agents.sort(cmp)
        for row, agent in component.agents: 
            igTableNextRow(ImGuiTableRowFlags_None.int32, 0.0f)

            if igTableSetColumnIndex(0):          
                # Enable multi-select functionality       
                igSetNextItemSelectionUserData(row)
                var isSelected = ImGuiSelectionBasicStorage_Contains(component.selection, cast[ImGuiID](row))
                discard igSelectable_Bool(agent.agentId, isSelected, ImGuiSelectableFlags_SpanAllColumns.int32, vec2(0.0f, 0.0f))
                
                # Interact with session on double-click
                if igIsMouseDoubleClicked_Nil(ImGui_MouseButton_Left.int32):
                    component.interact()

            if igTableSetColumnIndex(1): 
                igText(agent.listenerId)
            if igTableSetColumnIndex(2): 
                igText(agent.ipInternal)
            if igTableSetColumnIndex(3): 
                igText(agent.ipExternal)
            if igTableSetColumnIndex(4): 

                igText(agent.username)
                if component.agentImpersonation.hasKey(agent.agentId):
                    igSameLine(0.0f, textSpacing)
                    igText(fmt"[{component.agentImpersonation[agent.agentId]}]")

            if igTableSetColumnIndex(5): 
                igText(agent.hostname)
            if igTableSetColumnIndex(6): 
                igText(agent.domain)
            if igTableSetColumnIndex(7): 
                igText(agent.os)
            if igTableSetColumnIndex(8): 
                igText(agent.process)
            if igTableSetColumnIndex(9): 
                igText($agent.pid)
            if igTableSetColumnIndex(10): 
                let duration = now() - agent.firstCheckin.fromUnix().local()
                let totalSeconds = duration.inSeconds
                    
                let hours = totalSeconds div 3600
                let minutes = (totalSeconds mod 3600) div 60
                let seconds = totalSeconds mod 60
                
                igText(fmt"{hours:02d}:{minutes:02d}:{seconds:02d} ago")

            if igTableSetColumnIndex(11): 
                let duration = now() - component.agentActivity[agent.agentId].fromUnix().local()
                let totalSeconds = duration.inSeconds
                
                let hours = totalSeconds div 3600
                let minutes = (totalSeconds mod 3600) div 60
                let seconds = totalSeconds mod 60
                
                let timeText = fmt"{hours:02d}:{minutes:02d}:{seconds:02d} ago"
                if totalSeconds > agent.sleep: 
                    igTextColored(GRAY, timeText)
                else: 
                    igText(timeText)

        # Handle right-click context menu
        # Right-clicking the table header to hide/show columns or reset the layout is only possible when no sessions are selected
        if component.selection[].Size > 0 and igBeginPopupContextWindow("TableContextMenu", ImGui_PopupFlags_MouseButtonRight.int32): 

            if igMenuItem("Interact", nil, false, true): 
                component.interact()
                igCloseCurrentPopup()
        
            if igBeginMenu("Exit", true):
                if igMenuItem("Process", nil, false, true): 
                    for i, agent in component.agents:
                        if ImGuiSelectionBasicStorage_Contains(component.selection, cast[ImGuiID](i)):
                            if component.consoles[].hasKey(agent.agentId):
                                component.consoles[][agent.agentId].handleAgentCommand(connection, "exit process")
                            else: 
                                let task = createTask(agent.agentId, agent.listenerId, getCommandByType(CMD_EXIT), @["process"])
                                connection.sendAgentTask(agent.agentId, "exit process", task)

                    ImGuiSelectionBasicStorage_Clear(component.selection)
                    igCloseCurrentPopup()

                if igMenuItem("Thread", nil, false, true):
                    for i, agent in component.agents:
                        if ImGuiSelectionBasicStorage_Contains(component.selection, cast[ImGuiID](i)):
                            if component.consoles[].hasKey(agent.agentId):
                                component.consoles[][agent.agentId].handleAgentCommand(connection, "exit thread") 
                            else: 
                                let task = createTask(agent.agentId, agent.listenerId, getCommandByType(CMD_EXIT), @["thread"])
                                connection.sendAgentTask(agent.agentId, "exit thread", task)

                    ImGuiSelectionBasicStorage_Clear(component.selection)
                    igCloseCurrentPopup()

                igEndMenu()

            igSeparator()

            if igMenuItem("Remove", nil, false, true): 
                # Update agents table with only non-selected ones
                var newAgents: seq[UIAgent] = @[]
                for i, agent in component.agents:
                    if not ImGuiSelectionBasicStorage_Contains(component.selection, cast[ImGuiID](i)):
                        newAgents.add(agent)
                    else: 
                        # Send message to team server to remove delete the agent from the database and stop it from re-appearing when the client is restarted
                        connection.sendAgentRemove(agent.agentId)

                component.agents = newAgents
                ImGuiSelectionBasicStorage_Clear(component.selection)
                igCloseCurrentPopup()

            igEndPopup()

        multiSelectIO = igEndMultiSelect()
        ImGuiSelectionBasicStorage_ApplyRequests(component.selection, multiSelectIO)
        
        # Auto-scroll to bottom
        if igGetScrollY() >= igGetScrollMaxY():
            igSetScrollHereY(1.0f)

        igEndTable()

    igEnd()