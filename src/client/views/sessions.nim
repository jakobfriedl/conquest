import times, tables, strformat
import imguin/[cimgui, glfw_opengl, simple]

import ./console
import ../utils/appImGui
import ../../common/[types, utils]

type 
    SessionsTableComponent = ref object of RootObj
        title: string 
        agents: seq[Agent]
        selection: ptr ImGuiSelectionBasicStorage
        consoles: ptr Table[string, ConsoleComponent]

let exampleAgents: seq[Agent] = @[
  Agent(
    agentId: "DEADBEEF",
    listenerId: "L1234567",
    username: "alice",
    hostname: "DESKTOP-01",
    domain: "corp.local",
    ip: "192.168.1.10",
    os: "Windows 10",
    process: "explorer.exe",
    pid: 2340,
    elevated: true,
    sleep: 60,
    tasks: @[],
    firstCheckin: now() - initDuration(hours = 2),
    latestCheckin: now(),
    sessionKey: [byte 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]
  ),
  Agent(
    agentId: "FACEDEAD",
    listenerId: "L7654321",
    username: "bob",
    hostname: "LAPTOP-02",
    domain: "corp.local",
    ip: "10.0.0.5",
    os: "Windows 11",
    process: "cmd.exe",
    pid: 4567,
    elevated: false,
    sleep: 120,
    tasks: @[],
    firstCheckin: now() - initDuration(hours = 1, minutes = 30),
    latestCheckin: now() - initDuration(minutes = 5),
    sessionKey: [byte 31, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0]
  ),
  Agent(
    agentId: "C9D8E7F6",
    listenerId: "L2468135",
    username: "charlie",
    hostname: "SERVER-03",
    domain: "child.corp.local",
    ip: "172.16.0.20",
    os: "Windows Server 2019",
    process: "powershell.exe",
    pid: 7890,
    elevated: true,
    sleep: 30,
    tasks: @[],
    firstCheckin: now() - initDuration(hours = 3, minutes = 15),
    latestCheckin: now() - initDuration(minutes = 10),
    sessionKey: [byte 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
  ),
  Agent(
    agentId: "G1H2I3J5",
    listenerId: "L1357924",
    username: "diana",
    hostname: "WORKSTATION-04",
    domain: "external.local",
    ip: "192.168.2.15",
    os: "Windows 10",
    process: "chrome.exe",
    pid: 3210,
    elevated: false,
    sleep: 90,
    tasks: @[],
    firstCheckin: now() - initDuration(hours = 4),
    latestCheckin: now() - initDuration(minutes = 2),
    sessionKey: [byte 5, 4, 3, 2, 1, 0, 31, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6]
  )
]

proc SessionsTable*(title: string, consoles: ptr Table[string, ConsoleComponent]): SessionsTableComponent = 
    result = new SessionsTableComponent
    result.title = title
    result.agents = exampleAgents
    result.selection = ImGuiSelectionBasicStorage_ImGuiSelectionBasicStorage()
    result.consoles = consoles

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


proc draw*(component: SessionsTableComponent, showComponent: ptr bool) = 
    igBegin(component.title, showComponent, 0)
    defer: igEnd() 

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
        ImGui_TableFlags_SizingStretchProp.int32
    )

    let cols: int32 = 8
    if igBeginTable("Sessions", cols, tableFlags, vec2(0.0f, 0.0f), 0.0f):

        igTableSetupColumn("AgentID", ImGuiTableColumnFlags_NoReorder.int32 or ImGuiTableColumnFlags_NoHide.int32, 0.0f, 0)
        igTableSetupColumn("Address", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Username", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Hostname", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("OS", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Process", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("PID", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
        igTableSetupColumn("Activity", ImGuiTableColumnFlags_None.int32, 0.0f, 0)

        igTableSetupScrollFreeze(0, 1)
        igTableHeadersRow()
        
        var multiSelectIO = igBeginMultiSelect(ImGuiMultiSelectFlags_ClearOnEscape.int32 or ImGuiMultiSelectFlags_BoxSelect1d.int32, component.selection[].Size, int32(component.agents.len())) 
        ImGuiSelectionBasicStorage_ApplyRequests(component.selection, multiSelectIO)

        for row in 0 ..< component.agents.len(): 
            
            igTableNextRow(ImGuiTableRowFlags_None.int32, 0.0f)
            let agent = component.agents[row]

            if igTableSetColumnIndex(0):          
                # Enable multi-select functionality       
                igSetNextItemSelectionUserData(row)
                var isSelected = ImGuiSelectionBasicStorage_Contains(component.selection, cast[ImGuiID](row))
                discard igSelectable_Bool(agent.agentId, isSelected, ImGuiSelectableFlags_SpanAllColumns.int32, vec2(0.0f, 0.0f))
                
                # Interact with session on double-click
                if igIsMouseDoubleClicked_Nil(ImGui_MouseButton_Left.int32):
                    component.interact()
            
            if igTableSetColumnIndex(1): 
                igText(agent.ip)
            if igTableSetColumnIndex(2): 
                igText(agent.username)
            if igTableSetColumnIndex(3): 
                igText(agent.hostname)
            if igTableSetColumnIndex(4): 
                igText(agent.os)
            if igTableSetColumnIndex(5): 
                igText(agent.process)
            if igTableSetColumnIndex(6): 
                igText($agent.pid)
            if igTableSetColumnIndex(7): 
                igText(agent.latestCheckin.format("yyyy-MM-dd HH:mm:ss"))

        # Handle right-click context menu
        # Right-clicking the table header to hide/show columns or reset the layout is only possible when no sessions are selected
        if component.selection[].Size > 0 and igBeginPopupContextWindow("TableContextMenu", ImGui_PopupFlags_MouseButtonRight.int32): 

            if igMenuItem("Interact", nil, false, true): 
                component.interact()
                igCloseCurrentPopup()
        
            if igMenuItem("Remove", nil, false, true): 
                # Update agents table with only non-selected ones
                var newAgents: seq[Agent] = @[]
                for i in 0 ..< component.agents.len():
                    if not ImGuiSelectionBasicStorage_Contains(component.selection, cast[ImGuiID](i)):
                        newAgents.add(component.agents[i])

                component.agents = newAgents
                ImGuiSelectionBasicStorage_Clear(component.selection)
                igCloseCurrentPopup()

            igEndPopup()

        multiSelectIO = igEndMultiSelect()
        ImGuiSelectionBasicStorage_ApplyRequests(component.selection, multiSelectIO)
        
        igEndTable()


    