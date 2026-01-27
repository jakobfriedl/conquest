import times, tables, strformat, strutils, sequtils, algorithm
import imguin/[cimgui, glfw_opengl, simple]

import ../utils/[appImGui, globals]
import ../core/[task, websocket]
import ./[console, moduleManager]
import ../../types/[common, client]

# type 
#     SessionsTableComponent* = ref object of RootObj
#         title: string 
#         agents*: seq[UIAgent]
#         selection: ptr ImGuiSelectionBasicStorage
#         consoles: ptr Table[string, ConsoleComponent]
#         focusedConsole*: string

proc SessionsTable*(title: string, showComponent: ptr bool): SessionsTableComponent = 
    result = new SessionsTableComponent
    result.title = title
    result.showComponent = showComponent
    result.agents = initTable[string, UIAgent]()
    result.selection = ImGuiSelectionBasicStorage_ImGuiSelectionBasicStorage()
    result.focusedConsole = ""

proc interact(component: SessionsTableComponent) = 
    var it: pointer = nil
    var row: ImGuiID

    while ImGuiSelectionBasicStorage_GetNextSelectedItem(component.selection, addr it, addr row):
        let agent = cq.sessions.agents.values().toSeq().sortedByIt(it.firstCheckin)[row]

        # Show console
        agent.console.showConsole = true

        # Set focus 
        component.focusedConsole = agent.consoleTitle
    
    component.selection.ImGuiSelectionBasicStorage_Clear()

proc draw*(component: SessionsTableComponent) = 
    igBegin(component.title.cstring, component.showComponent, 0)

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
        let agents = cq.sessions.agents.values().toSeq().sortedByIt(it.firstCheckin)

        for i, agent in agents: 
            igTableNextRow(ImGuiTableRowFlags_None.int32, 0.0f)

            if igTableSetColumnIndex(0):          
                # Enable multi-select functionality       
                igSetNextItemSelectionUserData(i)
                var isSelected = ImGuiSelectionBasicStorage_Contains(component.selection, cast[ImGuiID](i))
                
                # Highlight high integrity sessions in red
                if agent.elevated: 
                    igPushStyleColor_Vec4(ImGui_Col_Text.cint, CONSOLE_ERROR)

                discard igSelectable_Bool(agent.agentId.cstring, isSelected, ImGuiSelectableFlags_SpanAllColumns.int32, vec2(0.0f, 0.0f))
                
                if agent.elevated:
                    igPopStyleColor(1)

                # Interact with session on double-click
                if igIsMouseDoubleClicked_Nil(ImGui_MouseButton_Left.int32):
                    component.interact()

            if igTableSetColumnIndex(1): 
                igText(agent.listenerId.cstring)
            if igTableSetColumnIndex(2): 
                igText(agent.ipInternal.cstring)
            if igTableSetColumnIndex(3): 
                igText(agent.ipExternal.cstring)
            if igTableSetColumnIndex(4): 

                igText(agent.username.cstring)
                if agent.impersonationToken != "":
                    igSameLine(0.0f, textSpacing)
                    igText(fmt"[{component.agents[agent.agentId].impersonationToken}]".cstring)

            if igTableSetColumnIndex(5): 
                igText(agent.hostname.cstring)
            if igTableSetColumnIndex(6): 
                igText(agent.domain.cstring)
            if igTableSetColumnIndex(7): 
                igText(agent.os.cstring)
            if igTableSetColumnIndex(8): 
                igText(agent.process.cstring)
            if igTableSetColumnIndex(9): 
                igText(($agent.pid).cstring)
            if igTableSetColumnIndex(10): 
                let duration = now() - agent.firstCheckin.fromUnix().local()
                let totalSeconds = duration.inSeconds
                    
                let hours = totalSeconds div 3600
                let minutes = (totalSeconds mod 3600) div 60
                let seconds = totalSeconds mod 60
                
                igText(fmt"{hours:02d}:{minutes:02d}:{seconds:02d} ago".cstring)

            if igTableSetColumnIndex(11): 
                let duration = now() - component.agents[agent.agentId].latestCheckin.fromUnix().local()
                let totalSeconds = duration.inSeconds
                
                let hours = totalSeconds div 3600
                let minutes = (totalSeconds mod 3600) div 60
                let seconds = totalSeconds mod 60
                
                let timeText = fmt"{hours:02d}:{minutes:02d}:{seconds:02d} ago"
                if totalSeconds > agent.sleep: 
                    igTextColored(GRAY, timeText.cstring)
                else: 
                    igText(timeText.cstring)

        # Handle right-click context menu
        # Right-clicking the table header to hide/show columns or reset the layout is only possible when no sessions are selected
        if component.selection[].Size > 0 and igBeginPopupContextWindow("TableContextMenu", ImGui_PopupFlags_MouseButtonRight.int32): 

            if igMenuItem("Interact", nil, false, true): 
                component.interact()
                igCloseCurrentPopup()
        
            # Menu to open a browser focused on the selected agent
            if igBeginMenu("Browse", true):
                if igMenuItem("Processes", nil, false, true):
                    var it: pointer = nil
                    var row: ImGuiID

                    if ImGuiSelectionBasicStorage_GetNextSelectedItem(component.selection, addr it, addr row):
                        let agent = agents[row]
                        
                        cq.processBrowser.showComponent[] = true
                        let agentIndex = agents.find(agent)
                        if agentIndex >= 0:
                            cq.processBrowser.agent = int32(agentIndex + 1)

                    igSetWindowFocus_Str(WIDGET_PROCESS_BROWSER)         
                    igCloseCurrentPopup()

                if igMenuItem("Filesystem", nil, false, true):
                    var it: pointer = nil
                    var row: ImGuiID

                    if ImGuiSelectionBasicStorage_GetNextSelectedItem(component.selection, addr it, addr row):
                        let agent = agents[row]
                        
                        cq.fileBrowser.showComponent[] = true
                        let agentIndex = agents.find(agent)
                        if agentIndex >= 0:
                            cq.fileBrowser.agent = int32(agentIndex + 1)

                    igSetWindowFocus_Str(WIDGET_FILE_BROWSER)         
                    igCloseCurrentPopup()

                igEndMenu()

            # Menu to copy fields of the agent object to clipboard
            if igBeginMenu("Copy", true): 
                const copyableFields = [
                    ("agentId", "AgentID"),
                    ("listenerId", "ListenerID"),
                    ("username", "Username"),
                    ("impersonationToken", "Impersonation Token"),
                    ("hostname", "Hostname"),
                    ("domain", "Domain"),
                    ("ipInternal", "IP (Internal)"),
                    ("ipExternal", "IP (External)"),
                    ("os", "Operating System"),
                    ("process", "Process Name"),
                    ("pid", "ProcessID"),
                    ("elevated", "IsElevated"),
                    ("sleep", "Sleep"),
                    ("jitter", "Jitter")
                ]
                
                for (fieldName, displayName) in copyableFields:
                    if igMenuItem(displayName.cstring, nil, false, true):
                        var toCopy: string = ""
                        for i, agent in agents:
                            if ImGuiSelectionBasicStorage_Contains(component.selection, cast[ImGuiID](i)):
                                let value = case fieldName:
                                    of "agentId": agent.agentId
                                    of "listenerId": agent.listenerId
                                    of "username": agent.username
                                    of "impersonationToken": agent.impersonationToken
                                    of "hostname": agent.hostname
                                    of "domain": agent.domain
                                    of "ipInternal": agent.ipInternal
                                    of "ipExternal": agent.ipExternal
                                    of "os": agent.os
                                    of "process": agent.process
                                    of "pid": $agent.pid
                                    of "elevated": $agent.elevated
                                    of "sleep": $agent.sleep
                                    of "jitter": $agent.jitter
                                    else: ""
                                
                                toCopy &= value & "\n"
                        
                        igSetClipboardText(toCopy.strip().cstring)
                        igCloseCurrentPopup()
                
                igEndMenu()

            # Menu to exit the agent process in different ways
            if igBeginMenu("Exit", true):
                if igMenuItem("Process", nil, false, true): 
                    for i, agent in agents:
                        if ImGuiSelectionBasicStorage_Contains(component.selection, cast[ImGuiID](i)):
                            agent.console.handleAgentCommand("exit process")

                    ImGuiSelectionBasicStorage_Clear(component.selection)
                    igCloseCurrentPopup()

                if igMenuItem("Thread", nil, false, true):
                    for i, agent in agents:
                        if ImGuiSelectionBasicStorage_Contains(component.selection, cast[ImGuiID](i)):
                            agent.console.handleAgentCommand("exit thread") 

                    ImGuiSelectionBasicStorage_Clear(component.selection)
                    igCloseCurrentPopup()

                if igMenuItem("Self-Destruct", nil, false, true):
                    for i, agent in agents:
                        if ImGuiSelectionBasicStorage_Contains(component.selection, cast[ImGuiID](i)):
                            agent.console.handleAgentCommand("self-destruct")

                    ImGuiSelectionBasicStorage_Clear(component.selection)
                    igCloseCurrentPopup()
                
                igEndMenu()

            igSeparator()

            # Menu item to remove an agent from the team server database
            if igMenuItem("Remove", nil, false, true): 
                for i, agent in agents:
                    if ImGuiSelectionBasicStorage_Contains(component.selection, cast[ImGuiID](i)):
                        component.agents.del(agent.agentId)
                        cq.connection.sendAgentRemove(agent.agentId)

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