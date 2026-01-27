import imguin/[cimgui, glfw_opengl]
import ./widgets/textarea
import ../utils/[appImGui, globals]
import ../../types/client
export addItem

proc Eventlog*(title: string, showComponent: ptr bool): EventlogComponent = 
    result = new EventlogComponent
    result.title = title
    result.showComponent = showComponent
    result.textarea = Textarea(showTimestamps = false)

proc draw*(component: EventlogComponent) = 
    igBegin(component.title.cstring, component.showComponent, 0)
    defer: igEnd() 

    component.textarea.draw(vec2(-1.0f, -1.0f))