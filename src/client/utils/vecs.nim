import imguin/cimgui

type
    Vec2* = ImVec2
    Vec4* = ImVec4

proc vec2*(x, y: auto): ImVec2 =
    ImVec2(x: x.cfloat, y: y.cfloat)

proc vec4*(x, y, z, w: auto): ImVec4 =
    ImVec4(x: x.cfloat , y: y.cfloat , z: z.cfloat , w: w.cfloat)
