import imguin/[cimgui, glfw_opengl]
import ../../utils/[appImGui, globals]
import ../../core/websocket
import ../../../types/[client, event]

proc NoteModal*(): NoteModalComponent =
    result = new NoteModalComponent
    zeroMem(addr result.note[0], MAX_INPUT_LENGTH)

proc resetModalValues(component: NoteModalComponent) =
    component.editingItem = nil
    zeroMem(addr component.note[0], MAX_INPUT_LENGTH)

proc setEdit*(component: NoteModalComponent, item: LootItem) =
    component.editingItem = item
    zeroMem(addr component.note[0], MAX_INPUT_LENGTH)
    copyMem(addr component.note[0], item.note.cstring, min(item.note.len, MAX_INPUT_LENGTH - 1))

proc draw*(component: NoteModalComponent) =
    let textSpacing = igGetStyle().ItemSpacing.x
    let vp = igGetMainViewport()
    var center = ImGuiViewport_GetCenter(vp)
    igSetNextWindowPos(center, ImGuiCond_Appearing.int32, vec2(0.5f, 0.5f))
    igSetNextWindowSize(vec2(max(500.0f, vp.Size.x * 0.25), 0.0f), ImGuiCond_Always.int32)

    var show = true
    if igBeginPopupModal("Edit Note", addr show, ImGuiWindowFlags_None.int32):
        defer: igEndPopup()

        igText("Note: ")
        var availableSize = igGetContentRegionAvail()
        igSetNextItemWidth(availableSize.x)
        if igIsWindowAppearing(): igSetKeyboardFocusHere(0)
        igInputTextMultiline("##InputNote", cast[cstring](addr component.note[0]), MAX_INPUT_LENGTH, vec2(0.0f, 3.0f * igGetTextLineHeightWithSpacing()), ImGui_InputTextFlags_None.int32, nil, nil)

        igDummy(vec2(0.0f, 10.0f))
        igSeparator()
        igDummy(vec2(0.0f, 10.0f))

        availableSize = igGetContentRegionAvail()
        if igButton("Save", vec2(availableSize.x * 0.5 - textSpacing * 0.5, 0.0f)):
            # Update note only
            let item = LootItem(
                lootId: component.editingItem.lootId,
                agentId: component.editingItem.agentId,
                host: component.editingItem.host,
                timestamp: component.editingItem.timestamp,
                itemType: component.editingItem.itemType,
                path: component.editingItem.path,
                remotePath: component.editingItem.remotePath,
                size: component.editingItem.size,
                credType: component.editingItem.credType,
                username: component.editingItem.username,
                value: component.editingItem.value,
                note: $cast[cstring](addr component.note[0])
            )

            cq.connection.sendLootModify(item, @[])
            component.resetModalValues()
            igCloseCurrentPopup()

        igSameLine(0.0f, textSpacing)
        if igButton("Close", vec2(availableSize.x * 0.5 - textSpacing * 0.5, 0.0f)):
            component.resetModalValues()
            igCloseCurrentPopup()
