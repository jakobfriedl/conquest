import imguin/cimgui

type
  Vec2* = ImVec2
  Vec4* = ImVec4

proc vec2*(x, y: auto): ImVec2 =
  ImVec2(x: x.cfloat, y: y.cfloat)

proc vec4*(x, y, z, w: auto): ImVec4 =
  ImVec4(x: x.cfloat , y: y.cfloat , z: z.cfloat , w: w.cfloat)

# Tooltips 
proc setTooltip*(str:string, delay=Imgui_HoveredFlags_DelayNormal.cint, color=ImVec4(x: 1.0, y: 1.0, z: 1.0, w: 1.0)) =
  if igIsItemHovered(delay):
    if igBeginTooltip():
      igPushStyleColorVec4(ImGuiCol_Text.cint, color)
      igText(str)
      igPopStyleColor(1)
      igEndTooltip()

# IM_COL32
proc IM_COL32*(a,b,c,d:uint32): ImU32  =
  return igGetColorU32_Vec4(vec4(a.cfloat/255, b.cfloat/255, c.cfloat/255, d.cfloat/255))

# Definitions from imguin/simple (https://github.com/dinau/imguin/blob/main/src/imguin/simple.nim)
{.push discardable.} # Push discardable applies the {.discardable.} pragma to all functions until the {.pop.} pragma is reached
when false:
  type CColor* = object
    x,y,z,w: cfloat

  proc array3(self:ccolor): array[3,cfloat] =
    result = cast[array[3,cfloat]]([self.x,self.y,self.z])

  proc newCColor(col:ImVec4):ccolor =
    result.x = col.x
    result.y = col.y
    result.z = col.z
    result.w = col.w

  proc vec4*(self:ccolor): ImVec4 =
    ImVec4(x:self.x,y:self.y,z:self.z,w:self.z)

else:
  type CColor* {.union.} = object
    elm*: tuple[x,y,z,w: cfloat]
    array3*: array[3, cfloat]
    vec4*: ImVec4

proc igInputTextWithHint*(label: string, hint: string, buf: string, bufsize: int = buf.len, flags:Imguiinputtextflags = 0.Imguiinputtextflags, callback: ImguiInputTextCallback = nil, userdata: pointer = nil):  bool {.inline,discardable.} =
  igInputTextWithHint(label.cstring, hint.cstring, buf.cstring, bufsize.cuint, flags, callback, userdata)

proc igPlotLines*[T](label:string, arry: openArray[T], size:int= arry.len, offset:int = 0, overlayText:string = "", smin:float = igGetFLTMax(), smax:float = igGetFLTMax(), graphSize:Imvec2 = ImVec2(x:0,y:0), stride:int = sizeof(cfloat)) {.inline.} =
  igPlotLinesFloatPtr(label.cstring, cast[ptr T](addr arry), size.cint, offset.cint, overlayText.cstring, smin.cfloat, smax.cfloat, graphSize, stride.cint)        

when defined(ImKnobsEnable) or defined(ImKnobs):
  proc IgKnobEx*(label: cstring; p_value: ptr cfloat; v_min: cfloat; v_max: cfloat; speed: cfloat; format: cstring; variant: IgKnobVariant; size: cfloat; flags: IgKnobFlags; steps: cint; angle_min: cfloat; angle_max: cfloat): bool =
    return IgKnobFloat(label, p_value, v_min, v_max, speed, format, variant, size, flags, steps, angle_min, angle_max)

  proc IgKnob*(label: cstring; p_value: ptr cfloat; v_min: cfloat; v_max: cfloat): bool =
    return IgKnobFloat(label, p_value, v_min, v_max, 0, "%.3f", IgKnobVariant_Tick.IgKnobVariant,0, cast[IgKnobFlags](0),10,-1,-1)

proc igPushStyleColor*(idx: ImGuiCol; col: ImU32) = igPushStyleColor_U32(idx, col)
proc igPushStyleColor*(idx: ImGuiCol; col: ImVec4) = igPushStyleColor_Vec4(idx, col)
proc igSameLine*() = igSameLine(0.0, -1.0)

proc igBeginMenuEx*(label: cstring, icon: cstring, enabled: bool = true): bool {.importc: "igBeginMenuEx".}
proc igMenuItem*(label: cstring, shortcut: cstring = nil, selected: bool = false, enabled: bool = true): bool {.importc: "igMenuItem_Bool".}
proc igMenuItem*(label: cstring, shortcut: cstring, p_selected: ptr bool, enabled: bool = true): bool {.importc: "igMenuItem_BoolPtr".}
proc igMenuItemEx*(label: cstring, icon: cstring, shortcut: cstring = nil, selected: bool = false, enabled: bool = true): bool {.importc: "igMenuItemEx".}

proc igBeginChild*(str_id: cstring, size: ImVec2 = ImVec2(x: 0, y: 0), border: bool = false, flags: ImGuiWindowFlags = 0.ImGuiWindowFlags): bool {.importc: "igBeginChild_Str".}
proc igBeginChild*(id: ImGuiID, size: ImVec2 = ImVec2(x: 0, y: 0), border: bool = false, flags: ImGuiWindowFlags = 0.ImGuiWindowFlags): bool {.importc: "igBeginChild_ID".}

when not defined(igGetIO):
  template igGetIO*(): ptr ImGuiIO =
    igGetIO_Nil()

{.pop.}

# Fonts 
proc pointToPx*(point: float32): cfloat = 
    return ((point * 96) / 72).cfloat

proc setupFonts*(): (bool, string, string) = 
    
    let io = igGetIO() 
    let 
        fontPath = "/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf"
        fontName = "NotoMono-Regular"
        fontSize = pointToPx(18.0f)

    # Set base font
    io.Fonts.ImFontAtlas_AddFontFromFileTTF(fontPath.cstring, fontSize, nil, nil)

    result = (true, fontPath, fontName)
    
