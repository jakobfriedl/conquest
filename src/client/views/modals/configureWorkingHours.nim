import imguin/[cimgui, glfw_opengl]
import ../../utils/appImGui
import ../../../common/types

type 
    WorkingHoursModalComponent* = ref object of RootObj
        workingHours: WorkingHours

proc WorkingHoursModal*(): WorkingHoursModalComponent =
    result = new WorkingHoursModalComponent
    result.workingHours = WorkingHours(
        enabled: false,
        startHour: 9, 
        startMinute: 0,
        endHour: 17,
        endMinute: 0
    )

proc resetModalValues*(component: WorkingHoursModalComponent) = 
    component.workingHours = WorkingHours(
        enabled: false,
        startHour: 9, 
        startMinute: 0,
        endHour: 17,
        endMinute: 0
    )

proc wrapValue(value: int32, max: int32): int32 =
    result = value mod max
    if result < 0:
        result += max

proc draw*(component: WorkingHoursModalComponent): WorkingHours =
    result = component.workingHours

    # Center modal
    let vp = igGetMainViewport()
    var center: ImVec2
    ImGuiViewport_GetCenter(addr center, vp)
    igSetNextWindowPos(center, ImGuiCond_Appearing.int32, vec2(0.5f, 0.5f))
    
    let modalWidth = max(400.0f, vp.Size.x * 0.2)
    igSetNextWindowSize(vec2(modalWidth, 0.0f), ImGuiCond_Always.int32)
    
    var show = true
    let windowFlags = ImGuiWindowFlags_None.int32
    if igBeginPopupModal("Configure Working Hours", addr show, windowFlags):
        defer: igEndPopup()
        
        let textSpacing = igGetStyle().ItemSpacing.x
        var availableSize: ImVec2
    
        var charSize: ImVec2 
        igCalcTextSize(addr charSize, "00", nil, false, -1.0)
        let charWidth = charSize.x + 10.0f
        
        igText("Start: ")
        igSameLine(0.0f, textSpacing)
        igPushItemWidth(charWidth)
        igInputScalar("##StartHours", ImGuiDataType_S32.int32, addr component.workingHours.startHour, nil, nil, "%02d", 0)
        igPopItemWidth()
        igSameLine(0.0f, 0.0f)
        igText(":")
        igSameLine(0.0f, 0.0f)
        igPushItemWidth(charWidth)
        igInputScalar("##StartMinute", ImGuiDataType_S32.int32, addr component.workingHours.startMinute, nil, nil, "%02d", 0)
        igPopItemWidth()
        
        igText("End:   ")
        igSameLine(0.0f, textSpacing)
        igPushItemWidth(charWidth)
        igInputScalar("##EndHour", ImGuiDataType_S32.int32, addr component.workingHours.endHour, nil, nil, "%02d", 0)
        igPopItemWidth()
        igSameLine(0.0f, 0.0f)
        igText(":")
        igSameLine(0.0f, 0.0f)
        igPushItemWidth(charWidth)
        igInputScalar("##EndMinute", ImGuiDataType_S32.int32, addr component.workingHours.endMinute, nil, nil, "%02d", 0)
        igPopItemWidth()

        # Wrap time values
        component.workingHours.startHour = wrapValue(component.workingHours.startHour, 24)
        component.workingHours.endHour = wrapValue(component.workingHours.endHour, 24)
        component.workingHours.startMinute = wrapValue(component.workingHours.startMinute, 60)
        component.workingHours.endMinute = wrapValue(component.workingHours.endMinute, 60)
        
        igGetContentRegionAvail(addr availableSize)
        
        igDummy(vec2(0.0f, 10.0f))
        
        if igButton("Configure", vec2(availableSize.x * 0.5 - textSpacing * 0.5, 0.0f)):
            component.workingHours.enabled = true 
            result = component.workingHours
            component.resetModalValues()
            igCloseCurrentPopup()
        
        igSameLine(0.0f, textSpacing)
        
        if igButton("Cancel", vec2(availableSize.x * 0.5 - textSpacing * 0.5, 0.0f)):
            component.resetModalValues()
            igCloseCurrentPopup()