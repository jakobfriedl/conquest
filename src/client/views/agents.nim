import times
import imguin/[cimgui, glfw_opengl, simple]
import ../utils/appImGui
import ../../common/[types]

type 
    AgentsTableComponent = ref object of RootObj
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

proc AgentsTable*(title: string): AgentsTableComponent = 
    result = new AgentsTableComponent
    result.title = title
    result.agents = exampleAgents

proc draw*(component: AgentsTableComponent, showComponent: ptr bool) = 
    igBegin(component.title, showComponent, 0)
    defer: igEnd() 

    igText("asd")
