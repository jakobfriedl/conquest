import times
import imguin/[cimgui, glfw_opengl, simple]
import ../utils/appImGui
import ../../common/[types]

type 
    ListenersTableComponent = ref object of RootObj
        title: string 
        listeners: seq[Listener]

let exampleListeners: seq[Listener] = @[
  Listener(
    listenerId: "L1234567",
    address: "192.168.1.1",
    port: 8080,
    protocol: HTTP
  ),
  Listener(
    listenerId: "L7654321",
    address: "10.0.0.2",
    port: 443,
    protocol: HTTP
  )
]

proc ListenersTable*(title: string): ListenersTableComponent = 
    result = new ListenersTableComponent
    result.title = title
    result.listeners = exampleListeners

proc draw*(component: ListenersTableComponent, showComponent: ptr bool) = 
    igSetNextWindowSize(vec2(800, 600), ImGuiCond_Once.int32)
    igBegin(component.title, showComponent, 0)
    defer: igEnd() 

    igText("Listeners")
