import strformat
import imguin/[cimgui, glfw_opengl, simple]
import ../utils/appImGui
import ../../common/[types]

type 
    ConsoleComponent* = ref object of RootObj
        agent: Agent
        showConsole*: bool

proc Console*(agent: Agent): ConsoleComponent = 
    result = new ConsoleComponent
    result.agent = agent
    result.showConsole = true

proc draw*(component: ConsoleComponent) = 
    igSetNextWindowSize(vec2(800, 600), ImGuiCond_Once.int32)

    # var showComponent = component.showConsole
    igBegin(fmt"[{component.agent.agentId}] {component.agent.username}@{component.agent.hostname}", addr component.showConsole, 0)
    defer: igEnd() 

    igText(component.agent.agentId)

    # component.showConsole = showComponent