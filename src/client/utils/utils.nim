import imguin/[cimgui]
import ./vecs

#---------------
#--- setTooltip
#---------------
proc setTooltip*(str:string, delay=Imgui_HoveredFlags_DelayNormal.cint, color=ImVec4(x: 1.0, y: 1.0, z: 1.0, w: 1.0)) =
    if igIsItemHovered(delay):
        if igBeginTooltip():
            igPushStyleColorVec4(ImGuiCol_Text.cint, color)
            igText(str)
            igPopStyleColor(1)
            igEndTooltip()

type
    Theme* = enum
        Light, Dark, Classic

# setTheme
proc setTheme*(themeName: Theme) =
    case themeName
    of Light:
        igStyleColorsLight(nil)
    of Dark:
        igStyleColorsDark(nil)
    of Classic:
        igStyleColorsClassic(nil)

# IM_COL32
proc IM_COL32*(a,b,c,d:uint32): ImU32    =
    return igGetColorU32_Vec4(vec4(a.cfloat/255, b.cfloat/255, c.cfloat/255, d.cfloat/255))
