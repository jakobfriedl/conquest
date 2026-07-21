import imguin/[cimgui, glfw_opengl]
import ../../types/client
import ../utils/appImGui

proc Targets*(title: string, showComponent: ptr bool): TargetsComponent =
    result = new TargetsComponent
    result.title = title
    result.showComponent = showComponent
     
proc draw*(component: TargetsComponent) =
    igBegin(component.title.cstring, component.showComponent, 0)
    defer: igEnd() 

