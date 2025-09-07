import times
import imguin/[cimgui, glfw_opengl, simple]
import ../utils/appImGui
import ../../common/[types]

type 
    SessionsTableComponent = ref object of RootObj
        title: string 
        agents: seq[Agent]


let exampleAgents: seq[Agent] = @[
  Agent(
    agentId: "DEADBEEF",
    listenerId: "L1234567",
    username: "alice",
    hostname: "DESKTOP-01",
    domain: "CORP",
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
    domain: "SALES",
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
  )
]

proc SessionsTable*(title: string): SessionsTableComponent = 
    result = new SessionsTableComponent
    result.title = title
    result.agents = exampleAgents

proc draw*(component: SessionsTableComponent, showComponent: ptr bool) = 
    igSetNextWindowSize(vec2(800, 600), ImGuiCond_Once.int32)

    igBegin(component.title, showComponent, 0)
    defer: igEnd() 

    let tableFlags = (
        ImGuiTableFlags_Resizable.int32 or 
        ImGuiTableFlags_Reorderable.int32 or 
        ImGuiTableFlags_Hideable.int32 or 
        ImGuiTableFlags_HighlightHoveredColumn.int32 or 
        ImGuiTableFlags_ContextMenuInBody.int32 or 
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

        for row in 0..< component.agents.len(): 
            igTableNextRow(ImGuiTableRowFlags_None.int32, 0.0f)
            let agent = component.agents[row]
            if igTableSetColumnIndex(0): 
                igText(agent.agentId)
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

        igEndTable()

    