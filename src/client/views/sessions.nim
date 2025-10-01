import times, tables, strformat, strutils, algorithm
import imguin/[cimgui, glfw_opengl, simple]

import ./console
import ../utils/[appImGui, colors]
import ../../common/[types, utils]

type 
    SessionsTableComponent* = ref object of RootObj
        title: string 
        agents*: seq[UIAgent]
        agentActivity*: Table[string, int64]            # Direct O(1) access to latest checkin
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

proc draw*(component: SessionsTableComponent, showComponent: ptr bool) = 
    igBegin(component.title, showComponent, 0)

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

    let cols: int32 = 11
    if igBeginTable("Sessions", cols, tableFlags, vec2(0.0f, 0.0f), 0.0f):

        igTableSetupColumn("AgentID", ImGuiTableColumnFlags_NoReorder.int32 or ImGuiTableColumnFlags_NoHide.int32, 0.0f, 0)
        igTableSetupColumn("ListenerID", ImGuiTableColumnFlags_DefaultHide.int32, 0.0f, 0)
        igTableSetupColumn("Address", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
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
                igText(agent.ip)
            if igTableSetColumnIndex(3): 
                igText(agent.username)
            if igTableSetColumnIndex(4): 
                igText(agent.hostname)
            if igTableSetColumnIndex(5): 
                igText(if agent.domain.isEmptyOrWhitespace(): "-" else: agent.domain)
            if igTableSetColumnIndex(6): 
                igText(agent.os)
            if igTableSetColumnIndex(7): 
                igText(agent.process)
            if igTableSetColumnIndex(8): 
                igText($agent.pid)
            if igTableSetColumnIndex(9): 
                let duration = now() - agent.firstCheckin.fromUnix().utc()
                let totalSeconds = duration.inSeconds
                
                let hours = totalSeconds div 3600
                let minutes = (totalSeconds mod 3600) div 60
                let seconds = totalSeconds mod 60
                
                let timeText = dateTime(2000, mJan, 1, hours.int, minutes.int, seconds.int).format("HH:mm:ss")
                igText(fmt"{timeText} ago")

            if igTableSetColumnIndex(10): 
                let duration = now() - component.agentActivity[agent.agentId].fromUnix().utc()
                let totalSeconds = duration.inSeconds
                
                let hours = totalSeconds div 3600
                let minutes = (totalSeconds mod 3600) div 60
                let seconds = totalSeconds mod 60
                
                let timeText = dateTime(2000, mJan, 1, hours.int, minutes.int, seconds.int).format("HH:mm:ss")

                if totalSeconds > agent.sleep: 
                    igTextColored(GRAY, fmt"{timeText} ago")
                else: 
                    igText(fmt"{timeText} ago")

        # Handle right-click context menu
        # Right-clicking the table header to hide/show columns or reset the layout is only possible when no sessions are selected
        if component.selection[].Size > 0 and igBeginPopupContextWindow("TableContextMenu", ImGui_PopupFlags_MouseButtonRight.int32): 

            if igMenuItem("Interact", nil, false, true): 
                component.interact()
                igCloseCurrentPopup()
        
            if igMenuItem("Remove", nil, false, true): 
                # Update agents table with only non-selected ones
                var newAgents: seq[UIAgent] = @[]
                for i, agent in component.agents:
                    if not ImGuiSelectionBasicStorage_Contains(component.selection, cast[ImGuiID](i)):
                        newAgents.add(agent)

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