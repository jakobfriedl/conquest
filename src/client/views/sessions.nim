import times, tables, strformat, strutils, sequtils, algorithm
import imguin/[cimgui, glfw_opengl, simple]

import ../../types/client
import ../utils/[appImGui, globals]
import ../core/websocket
import ./console
import ./widgets/graph

proc Sessions*(tableTitle: string, showTable: ptr bool, graphTitle: string,  showGraph: ptr bool): SessionsComponent =
    result = new SessionsComponent
    result.tableTitle = tableTitle
    result.showTable = showTable
    result.graphTitle = graphTitle
    result.showGraph = showGraph
    
    result.agents = initTable[string, UIAgent]()
    result.selection = ImGuiSelectionBasicStorage_ImGuiSelectionBasicStorage()
    result.focusedConsole = ""
    result.interact = false
    
    result.graph = Graph()

proc interact(component: SessionsComponent) =
    var it: pointer = nil
    var row: ImGuiID
    while ImGuiSelectionBasicStorage_GetNextSelectedItem(component.selection, addr it, addr row):
        let agent = cq.sessions.agents.values().toSeq().sortedByIt(it.firstCheckin)[row]
        agent.console.showConsole = true
        component.focusedConsole = agent.consoleTitle
    component.selection.ImGuiSelectionBasicStorage_Clear()

proc agentContextMenu(component: SessionsComponent, selected: seq[UIAgent], agents: seq[UIAgent]) =
    if igMenuItem("Interact", nil, false, true):
        selected[0].console.showConsole = true
        component.focusedConsole = selected[0].consoleTitle
        ImGuiSelectionBasicStorage_Clear(component.selection)
        igCloseCurrentPopup()
    
    if igBeginMenu("Browse", true):
        if igMenuItem("Processes", nil, false, true):
            cq.processBrowser.showComponent[] = true
            let idx = agents.find(selected[0])
            if idx >= 0: cq.processBrowser.agent = int32(idx + 1)
            igSetWindowFocus_Str(WIDGET_PROCESS_BROWSER)
            igCloseCurrentPopup()
        
        if igMenuItem("Filesystem", nil, false, true):
            cq.fileBrowser.showComponent[] = true
            let idx = agents.find(selected[0])
            if idx >= 0: cq.fileBrowser.agent = int32(idx + 1)
            igSetWindowFocus_Str(WIDGET_FILE_BROWSER)
            igCloseCurrentPopup()
        igEndMenu()
    
    if igBeginMenu("Copy", true):
        for label in ["AgentID", "ListenerID", "Username", "Impersonation Token", "Hostname", "Domain", "IP (Internal)", "IP (External)", "Operating System", "Process", "PID"]:
            if igMenuItem(label.cstring, nil, false, true):
                var toCopy = ""
                for agent in selected:
                    toCopy &= (case label:
                        of "AgentID": agent.agentId
                        of "ListenerID": agent.listenerId
                        of "Username": agent.username
                        of "Impersonation Token": agent.impersonationToken
                        of "Hostname": agent.hostname
                        of "Domain": agent.domain
                        of "IP (Internal)": agent.ipInternal
                        of "IP (External)": agent.ipExternal
                        of "Operating System": agent.os
                        of "Process": agent.process
                        of "PID": $agent.pid
                        else: "") & "\n"
                igSetClipboardText(toCopy.strip().cstring)
                igCloseCurrentPopup()
        igEndMenu()
    
    if igBeginMenu("Exit", true):
        if igMenuItem("Process", nil, false, true):
            for agent in selected: agent.console.handleAgentCommand("exit process")
            ImGuiSelectionBasicStorage_Clear(component.selection)
            igCloseCurrentPopup()
        if igMenuItem("Thread", nil, false, true):
            for agent in selected: agent.console.handleAgentCommand("exit thread")
            ImGuiSelectionBasicStorage_Clear(component.selection)
            igCloseCurrentPopup()
        if igMenuItem("Self-Destruct", nil, false, true):
            for agent in selected: agent.console.handleAgentCommand("self-destruct")
            ImGuiSelectionBasicStorage_Clear(component.selection)
            igCloseCurrentPopup()
        igEndMenu()
    
    igSeparator()
    
    if igMenuItem("Hide", nil, false, true):
        for agent in selected: component.agents[agent.agentId].hidden = true
        ImGuiSelectionBasicStorage_Clear(component.selection)
        igCloseCurrentPopup()
        
    if igMenuItem("Remove", nil, false, true):
        for agent in selected:
            component.agents.del(agent.agentId)
            cq.connection.sendAgentRemove(agent.agentId)
        ImGuiSelectionBasicStorage_Clear(component.selection)
        igCloseCurrentPopup()

proc draw*(component: SessionsComponent) =
    if component.showTable[]:
        igBegin(component.tableTitle.cstring, component.showTable, 0)
        defer: igEnd() 

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
            let agents = cq.sessions.agents.values().toSeq().sortedByIt(it.firstCheckin).filterIt(not it.hidden)

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
                        component.interact = true

                if igTableSetColumnIndex(1):
                    igTextWithTooltip(agent.listenerId)
                if igTableSetColumnIndex(2):
                    igTextWithTooltip(agent.ipInternal)
                if igTableSetColumnIndex(3):
                    igTextWithTooltip(agent.ipExternal)
                if igTableSetColumnIndex(4):

                    igTextWithTooltip(agent.username)
                    if agent.impersonationToken != "":
                        igSameLine(0.0f, textSpacing)
                        igText(fmt"[{component.agents[agent.agentId].impersonationToken}]".cstring)

                if igTableSetColumnIndex(5):
                    igTextWithTooltip(agent.hostname)
                if igTableSetColumnIndex(6):
                    igTextWithTooltip(agent.domain)
                if igTableSetColumnIndex(7):
                    igTextWithTooltip(agent.os)
                if igTableSetColumnIndex(8):
                    igTextWithTooltip(agent.process)
                if igTableSetColumnIndex(9):
                    igTextWithTooltip($agent.pid)
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
                        igTextColored(CONSOLE_GRAY, timeText.cstring)
                    else:
                        igText(timeText.cstring)

            # Handle right-click context menu
            # Right-clicking the table header to hide/show columns or reset the layout is only possible when no sessions are selected
            if component.selection[].Size > 0 and igBeginPopupContextWindow("TableContextMenu", ImGui_PopupFlags_MouseButtonRight.int32):
                let selectedAgents = agents.filterIt(ImGuiSelectionBasicStorage_Contains(component.selection, cast[ImGuiID](agents.find(it))))
                component.agentContextMenu(selectedAgents, agents)
                igEndPopup()

            multiSelectIO = igEndMultiSelect()
            ImGuiSelectionBasicStorage_ApplyRequests(component.selection, multiSelectIO)

            # Clear selection after double-click interaction
            if component.interact:
                ImGuiSelectionBasicStorage_Clear(component.selection)
                component.interact = false

            # Auto-scroll to bottom
            if igGetScrollY() >= igGetScrollMaxY():
                igSetScrollHereY(1.0f)

            igEndTable()

    if component.showGraph[]:
        igBegin(component.graphTitle.cstring, component.showGraph, 0)
        defer: igEnd()

        let selection = component.graph.draw(component.agents, cq.listeners.listeners)
        if selection != "" and component.agents.hasKey(selection):
            let sortedAgents = cq.sessions.agents.values().toSeq().sortedByIt(it.firstCheckin).filterIt(not it.hidden)
            
            if igIsMouseDoubleClicked_Nil(ImGui_MouseButton_Left.int32):
                component.agents[selection].console.showConsole = true
                component.focusedConsole = component.agents[selection].consoleTitle
            
            if igBeginPopup("GraphContextMenu", 0):
                component.agentContextMenu(@[component.agents[selection]], sortedAgents)
                igEndPopup()
