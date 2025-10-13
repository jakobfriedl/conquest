import strformat, strutils, times
import imguin/[cimgui, glfw_opengl, simple]
import ../utils/[appImGui, colors]
import ./widgets/textarea
import ../../common/types
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
    igBegin(component.title, showComponent, 0)
    defer: igEnd() 

    component.textarea.draw(vec2(-1.0f, -1.0f))