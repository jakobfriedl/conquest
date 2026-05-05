import strutils, times
import imguin/[cimgui, glfw_opengl]
import ../../utils/[appImGui, globals]
import ../../core/websocket
import ../../../common/utils
import ../../../types/[client, event]

proc CredentialModal*(): CredentialModalComponent =
    result = new CredentialModalComponent
    result.credType = 0
    zeroMem(addr result.host[0], 256)
    zeroMem(addr result.username[0], 256)
    zeroMem(addr result.value[0], 512)
    zeroMem(addr result.note[0], MAX_INPUT_LENGTH)

    for c in CredentialType.low .. CredentialType.high:
        result.credTypes.add($c)

proc resetModalValues(component: CredentialModalComponent) =
    component.credType = 0
    zeroMem(addr component.host[0], 256)
    zeroMem(addr component.username[0], 256)
    zeroMem(addr component.value[0], 512)
    zeroMem(addr component.note[0], MAX_INPUT_LENGTH)

proc draw*(component: CredentialModalComponent) =
    let textSpacing = igGetStyle().ItemSpacing.x

    let vp = igGetMainViewport()
    var center = ImGuiViewport_GetCenter(vp)
    igSetNextWindowPos(center, ImGuiCond_Appearing.int32, vec2(0.5f, 0.5f))
    igSetNextWindowSize(vec2(max(500.0f, vp.Size.x * 0.25), 0.0f), ImGuiCond_Always.int32)

    var show = true
    if igBeginPopupModal("Add Credential", addr show, ImGuiWindowFlags_None.int32):
        defer: igEndPopup()

        igText("Type:      ")
        igSameLine(0.0f, textSpacing)
        var availableSize = igGetContentRegionAvail()
        igSetNextItemWidth(availableSize.x)
        igCombo_Str("##InputCredType", addr component.credType, (component.credTypes.join("\0") & "\0").cstring, component.credTypes.len().int32)

        igText("Host:      ")
        igSameLine(0.0f, textSpacing)
        availableSize = igGetContentRegionAvail()
        igSetNextItemWidth(availableSize.x)
        igInputText("##InputHost", cast[cstring](addr component.host[0]), 256, ImGui_InputTextFlags_None.int32, nil, nil)

        igText("Username:  ")
        igSameLine(0.0f, textSpacing)
        availableSize = igGetContentRegionAvail()
        igSetNextItemWidth(availableSize.x)
        igInputText("##InputUsername", cast[cstring](addr component.username[0]), 256, ImGui_InputTextFlags_None.int32, nil, nil)

        igText("Value:     ")
        igSameLine(0.0f, textSpacing)
        availableSize = igGetContentRegionAvail()
        igSetNextItemWidth(availableSize.x)
        igInputText("##InputValue", cast[cstring](addr component.value[0]), 512, ImGui_InputTextFlags_None.int32, nil, nil)

        igText("Note:      ")
        igSameLine(0.0f, textSpacing)
        availableSize = igGetContentRegionAvail()
        igSetNextItemWidth(availableSize.x)
        igInputTextMultiline("##InputNote", cast[cstring](addr component.note[0]), MAX_INPUT_LENGTH, vec2(0.0f, 3.0f * igGetTextLineHeightWithSpacing()), ImGui_InputTextFlags_None.int32, nil, nil)

        igDummy(vec2(0.0f, 10.0f))
        igSeparator()
        igDummy(vec2(0.0f, 10.0f))

        availableSize = igGetContentRegionAvail()
        if igButton("Add", vec2(availableSize.x * 0.5 - textSpacing * 0.5, 0.0f)):
            let item = LootItem(
                lootId: generateUUID(),
                agentId: "",
                host: $cast[cstring](addr component.host[0]),
                timestamp: now().toTime().toUnix(),
                itemType: CREDENTIAL,
                credType: cast[CredentialType](component.credType),
                username: $cast[cstring](addr component.username[0]),
                value: $cast[cstring](addr component.value[0]),
                note: $cast[cstring](addr component.note[0])
            )
            cq.connection.sendLootStore(item, @[])
            component.resetModalValues()
            igCloseCurrentPopup()

        igSameLine(0.0f, textSpacing)
        if igButton("Close", vec2(availableSize.x * 0.5 - textSpacing * 0.5, 0.0f)):
            component.resetModalValues()
            igCloseCurrentPopup()
