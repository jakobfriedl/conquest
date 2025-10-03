import strformat, strutils, times
import imguin/[cimgui, glfw_opengl, simple]
import ../../utils/[appImGui, colors]
import ../../../common/types

type 
    LootDownloadsComponent* = ref object of RootObj
        title: string 


proc LootDownloads*(title: string): LootDownloadsComponent = 
    result = new LootDownloadsComponent
    result.title = title

proc draw*(component: LootDownloadsComponent, showComponent: ptr bool) = 
    igBegin(component.title, showComponent, 0)
    defer: igEnd() 

    igText("asd")
