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
    component.editingItem = nil
    zeroMem(addr component.host[0], 256)
    zeroMem(addr component.username[0], 256)
    zeroMem(addr component.value[0], 512)
    zeroMem(addr component.note[0], MAX_INPUT_LENGTH)

proc setEdit*(component: CredentialModalComponent, item: LootItem) = 
    component.editingItem = item
    component.credType = int32(ord(item.credType))
    zeroMem(addr component.host[0], 256)
    copyMem(addr component.host[0], item.host.cstring, min(item.host.len, 255))
    zeroMem(addr component.username[0], 256)
    copyMem(addr component.username[0], item.username.cstring, min(item.username.len, 255))
    zeroMem(addr component.value[0], 512)
    copyMem(addr component.value[0], item.value.cstring, min(item.value.len, 511))
    zeroMem(addr component.note[0], MAX_INPUT_LENGTH)
    copyMem(addr component.note[0], item.note.cstring, min(item.note.len, MAX_INPUT_LENGTH - 1))

proc draw*(component: CredentialModalComponent) =
    let
        textSpacing = igGetStyle().ItemSpacing.x
        modalLabel = if component.editingItem.isNil: "Add Credential" else: "Edit Credential"
        buttonLabel = if component.editingItem.isNil: "Add" else: "Save"

    let vp = igGetMainViewport()
    var center = ImGuiViewport_GetCenter(vp)
    igSetNextWindowPos(center, ImGuiCond_Appearing.int32, vec2(0.5f, 0.5f))
    igSetNextWindowSize(vec2(max(500.0f, vp.Size.x * 0.25), 0.0f), ImGuiCond_Always.int32)

    var show = true
    if igBeginPopupModal(modalLabel.cstring, addr show, ImGuiWindowFlags_None.int32):
        defer: igEndPopup()

        igText("Type:     ")
        igSameLine(0.0f, textSpacing)
        var availableSize = igGetContentRegionAvail()
        igSetNextItemWidth(availableSize.x)
        igCombo_Str("##InputCredType", addr component.credType, (component.credTypes.join("\0") & "\0").cstring, component.credTypes.len().int32)

        igDummy(vec2(0.0f, 10.0f))
        igSeparator()
        igDummy(vec2(0.0f, 10.0f))

        igText("Host:     ")
        igSameLine(0.0f, textSpacing)
        availableSize = igGetContentRegionAvail()
        igSetNextItemWidth(availableSize.x)
        if igIsWindowAppearing(): igSetKeyboardFocusHere(0)
        igInputText("##InputHost", cast[cstring](addr component.host[0]), 256, ImGui_InputTextFlags_None.int32, nil, nil)

        igText("Username: ")
        igSameLine(0.0f, textSpacing)
        availableSize = igGetContentRegionAvail()
        igSetNextItemWidth(availableSize.x)
        igInputText("##InputUsername", cast[cstring](addr component.username[0]), 256, ImGui_InputTextFlags_None.int32, nil, nil)

        igText("Value:    ")
        igSameLine(0.0f, textSpacing)
        availableSize = igGetContentRegionAvail()
        igSetNextItemWidth(availableSize.x)
        igInputText("##InputValue", cast[cstring](addr component.value[0]), 512, ImGui_InputTextFlags_None.int32, nil, nil)

        igDummy(vec2(0.0f, 10.0f))
        igSeparator()
        igDummy(vec2(0.0f, 10.0f))

        igText("Note:     ")
        igSameLine(0.0f, textSpacing)
        availableSize = igGetContentRegionAvail()
        igSetNextItemWidth(availableSize.x)
        igInputTextMultiline("##InputNote", cast[cstring](addr component.note[0]), MAX_INPUT_LENGTH, vec2(0.0f, 3.0f * igGetTextLineHeightWithSpacing()), ImGui_InputTextFlags_None.int32, nil, nil)

        igDummy(vec2(0.0f, 10.0f))
        igSeparator()
        igDummy(vec2(0.0f, 10.0f))

        availableSize = igGetContentRegionAvail()
        if igButton(buttonLabel.cstring, vec2(availableSize.x * 0.5 - textSpacing * 0.5, 0.0f)):            
            
            # Create or update credential 
            let item = LootItem(
                lootId: if component.editingItem.isNil: generateUUID() else: component.editingItem.lootId,
                agentId: if component.editingItem.isNil: "" else: component.editingItem.agentId,
                host: $cast[cstring](addr component.host[0]),
                timestamp: if component.editingItem.isNil: now().toTime().toUnix() else: component.editingItem.timestamp,
                itemType: CREDENTIAL,
                credType: cast[CredentialType](component.credType),
                username: $cast[cstring](addr component.username[0]),
                value: $cast[cstring](addr component.value[0]),
                note: $cast[cstring](addr component.note[0])
            )

            cq.connection.sendLootModify(item, @[])

            component.resetModalValues()
            igCloseCurrentPopup()

        igSameLine(0.0f, textSpacing)
        if igButton("Close", vec2(availableSize.x * 0.5 - textSpacing * 0.5, 0.0f)):
            component.resetModalValues()
            igCloseCurrentPopup()
