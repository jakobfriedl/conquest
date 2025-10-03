import strformat, strutils, times
import imguin/[cimgui, glfw_opengl, simple]
import ../../utils/[appImGui, colors]
import ../../../common/types

type 
    LootScreenshotsComponent* = ref object of RootObj
        title: string 


proc LootScreenshots*(title: string): LootScreenshotsComponent = 
    result = new LootScreenshotsComponent
    result.title = title

proc draw*(component: LootScreenshotsComponent, showComponent: ptr bool) = 
    igBegin(component.title, showComponent, 0)
    defer: igEnd() 

    igText("asd")
