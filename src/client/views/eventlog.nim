import times
import imguin/[cimgui, glfw_opengl, simple]
import ../utils/appImGui
import ../../common/[types]

type 
    EventlogComponent = ref object of RootObj
        title: string 

proc Eventlog*(title: string): EventlogComponent = 
    result = new EventlogComponent
    result.title = title

proc draw*(component: EventlogComponent, showComponent: ptr bool) = 
    igSetNextWindowSize(vec2(800, 600), ImGuiCond_Once.int32)
    igBegin(component.title, showComponent, 0)
    defer: igEnd() 

    igText("Eventlog")
