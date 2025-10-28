import strutils, sequtils, times
import imguin/[cimgui, glfw_opengl, simple]
import ../../utils/[appImGui, colors]

type 
    KillDateModalComponent* = ref object of RootObj
        killDateTime: ImPlotTime
        killDateLevel: cint
        killDateHour: cint
        killDateMinute: cint
        killDateSecond: cint

proc KillDateModal*(): KillDateModalComponent =
    result = new KillDateModalComponent
    result.killDateLevel = 0
    result.killDateTime = ImPlotTIme()

    # Initialize to current date
    # Note: ImPlot starts months at index 0, while nim's "times" module starts at 1, hence the subtraction 
    let now = now()    
    ImPlot_MakeTime(addr result.killDateTime, now.year.cint, (now.month.ord.cint - 1), now.monthday.cint, 0, 0, 0, 0) 

    result.killDateHour = 0
    result.killDateMinute = 0
    result.killDateSecond = 0

proc wrapValue(value: cint, max: cint): cint =
    result = value mod max
    if result < 0:
        result += max

proc resetModalValues*(component: KillDateModalComponent) = 
    component.killDateLevel = 0
    component.killDateTime = ImPlotTIme()
    
    # Initialize to current date
    let now = now() 
    ImPlot_MakeTime(addr component.killDateTime, now.year.cint, (now.month.ord.cint - 1), now.monthday.cint, 0, 0, 0, 0)  
    
    component.killDateHour = 0
    component.killDateMinute = 0
    component.killDateSecond = 0

proc draw*(component: KillDateModalComponent): int64 = 
    result = 0
    
    # Center modal
    let vp = igGetMainViewport()
    var center: ImVec2
    ImGuiViewport_GetCenter(addr center, vp)
    igSetNextWindowPos(center, ImGuiCond_Appearing.int32, vec2(0.5f, 0.5f))
    
    let modalWidth = max(400.0f, vp.Size.x * 0.2)
    igSetNextWindowSize(vec2(modalWidth, 0.0f), ImGuiCond_Always.int32)
    
    var show = true
    let windowFlags = ImGuiWindowFlags_None.int32
    if igBeginPopupModal("Configure Kill Date", addr show, windowFlags):
        defer: igEndPopup()
        
        let textSpacing = igGetStyle().ItemSpacing.x
        var availableSize: ImVec2
        
        # Date picker
        if ImPlot_ShowDatePicker("##KillDate", addr component.killDateLevel, addr component.killDateTime, nil, nil): 
            discard
        
        igDummy(vec2(0.0f, 10.0f))
        igSeparator()
        igDummy(vec2(0.0f, 10.0f))
        
        # Time input fields
        var charSize: ImVec2 
        igCalcTextSize(addr charSize, "00", nil, false, -1.0)
        let charWidth = charSize.x + 10.0f
        
        let dateText = component.killDateTime.S.fromUnix().utc().format("dd. MMMM yyyy") & '\0' 
        igInputText("##Text", dateText, dateText.len().csize_t, ImGui_InputTextFlags_ReadOnly.int32, nil, nil)
        igSameLine(0.0f, textSpacing)
    
        igPushItemWidth(charWidth)
        igInputScalar("##KillDateHour", ImGuiDataType_S32.int32, addr component.killDateHour, nil, nil, "%02d", 0)
        igPopItemWidth()
        igSameLine(0.0f, 0.0f)
        igText(":")
        igSameLine(0.0f, 0.0f)
        igPushItemWidth(charWidth)
        igInputScalar("##HillDateMinute", ImGuiDataType_S32.int32, addr component.killDateMinute, nil, nil, "%02d", 0)
        igPopItemWidth()
        igSameLine(0.0f, 0.0f)
        igText(":")        
        igSameLine(0.0f, 0.0f)
        igPushItemWidth(charWidth)
        igInputScalar("##KillDateSecond", ImGuiDataType_S32.int32, addr component.killDateSecond, nil, nil, "%02d", 0)
        igPopItemWidth()
        
        # Wrap time values
        component.killDateHour = wrapValue(component.killDateHour, 24)
        component.killDateMinute = wrapValue(component.killDateMinute, 60)
        component.killDateSecond = wrapValue(component.killDateSecond, 60)
        
        igGetContentRegionAvail(addr availableSize)
        
        igDummy(vec2(0.0f, 10.0f))
        igSeparator()
        igDummy(vec2(0.0f, 10.0f))
        
        # OK and Cancel buttons
        if igButton("OK", vec2(availableSize.x * 0.5 - textSpacing * 0.5, 0.0f)):
            result = component.killDateTime.S + (component.killDateHour * 3600) + (component.killDateMinute * 60) + component.killDateSecond
            component.resetModalValues()
            igCloseCurrentPopup()
        
        igSameLine(0.0f, textSpacing)
        
        if igButton("Cancel", vec2(availableSize.x * 0.5 - textSpacing * 0.5, 0.0f)):
            component.resetModalValues()
            igCloseCurrentPopup()