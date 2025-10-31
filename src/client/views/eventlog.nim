import imguin/[cimgui, glfw_opengl]
import ./widgets/textarea
import ../utils/appImGui
export addItem

type 
    EventlogComponent* = ref object of RootObj
        title: string 
        textarea*: TextareaWidget

proc Eventlog*(title: string): EventlogComponent = 
    result = new EventlogComponent
    result.title = title
    result.textarea = Textarea(showTimestamps = false)

proc draw*(component: EventlogComponent, showComponent: ptr bool) = 
    igBegin(component.title.cstring, showComponent, 0)
    defer: igEnd() 

    component.textarea.draw(vec2(-1.0f, -1.0f))