import tables, strformat, times
import imguin/[cimgui, glfw_opengl]
import ../../types/client
import ../utils/[appImGui, globals]

proc Targets*(title: string, showComponent: ptr bool): TargetsComponent =
    result = new TargetsComponent
    result.title = title
    result.showComponent = showComponent

proc getTargets(): seq[tuple[hostname: string, domain: string]] =
    var seen: seq[tuple[hostname: string, domain: string]] = @[]
    for agent in cq.sessions.agents.values():
        let key = (hostname: agent.hostname, domain: agent.domain)
        if key notin seen:
            seen.add(key)
    return seen

proc getAgents(target: tuple[hostname: string, domain: string]): seq[UIAgent] =
    for agent in cq.sessions.agents.values():
        if agent.hostname == target.hostname and agent.domain == target.domain:
            result.add(agent)

proc draw*(component: TargetsComponent) =
    igBegin(component.title.cstring, component.showComponent, 0)
    defer: igEnd()

    let availableSize = igGetContentRegionAvail()

    let tableFlags = (
        ImGui_TableFlags_Resizable.int32 or
        ImGui_TableFlags_RowBg.int32 or
        ImGui_TableFlags_BordersV.int32 or
        ImGui_TableFlags_BordersH.int32 or
        ImGui_TableFlags_ScrollY.int32 or
        ImGui_TableFlags_NoBordersInBodyUntilResize.int32 or
        ImGui_TableFlags_SizingStretchSame.int32
    )

    if igIsKeyPressed_Bool(ImGui_Key_Escape, false):
        component.selectedTarget.hostname.setLen(0)
        component.selectedTarget.domain.setLen(0)

    let hasSelection = component.selectedTarget.hostname != ""
    let childFlags = ImGui_ChildFlags_NavFlattened.int32 or (if hasSelection: ImGui_ChildFlags_ResizeX.int32 else: 0)
    if igBeginChild_Str((if hasSelection: "##LeftSplit".cstring else: "##LeftFull".cstring), vec2(if hasSelection: availableSize.x * 0.4f else: 0.0f, 0.0f), childFlags, 0):

        let cols: int32 = 5
        if igBeginTable("##Targets", cols, tableFlags, vec2(0.0f, 0.0f), 0.0f):
            igTableSetupColumn("Hostname", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
            igTableSetupColumn("Domain", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
            igTableSetupColumn("IP", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
            igTableSetupColumn("OS", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
            igTableSetupColumn("Sessions", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
            igTableSetupScrollFreeze(0, 1)
            igTableHeadersRow()

            for i, target in getTargets():
                let agents = target.getAgents()

                # Get metadata from first matching agent
                let match = agents[0]
                igTableNextRow(ImGuiTableRowFlags_None.int32, 0.0f)

                if igTableSetColumnIndex(0):
                    igPushID_Int(i.int32)
                    let isSelected = component.selectedTarget.hostname == target.hostname and component.selectedTarget.domain == target.domain
                    if igSelectable_Bool(target.hostname.cstring, isSelected, ImGuiSelectableFlags_SpanAllColumns.int32, vec2(0, 0)):
                        component.selectedTarget.hostname = target.hostname
                        component.selectedTarget.domain = target.domain
                    igPopID()

                if igTableSetColumnIndex(1):
                    igText(target.domain.cstring)
                if igTableSetColumnIndex(2):
                    igText(match.ipInternal.cstring)
                if igTableSetColumnIndex(3):
                    igText(match.os.cstring)
                if igTableSetColumnIndex(4):
                    igText(fmt"{agents.len}".cstring)

            igEndTable()

    igEndChild()

    if hasSelection:
        igSameLine(0.0f, 0.0f)
        if igBeginChild_Str("##Details", vec2(0.0f, 0.0f), ImGui_ChildFlags_Borders.int32, ImGui_WindowFlags_None.int32):
            let agents = component.selectedTarget.getAgents()
            if agents.len > 0:
                let match = agents[0]
                igTextColored(CONSOLE_INFO, fmt"{match.hostname} [{match.ipInternal}]".cstring)
                igSeparator()
                igDummy(vec2(0.0f, 5.0f))

                proc printRow(label: string, value: string) =
                    igTextColored(CONSOLE_GRAY, label.cstring)
                    igSameLine(165.0f, 0.0f)
                    igText(value.cstring)

                printRow("Hostname         :", match.hostname)
                printRow("Domain           :", if match.domain.len() > 0: match.domain else: "N/A")
                printRow("Operating System :", match.os)
                printRow("IP (Internal)    :", match.ipInternal)
                printRow("IP (External)    :", match.ipExternal)
                printRow("Sessions         :", $agents.len)

                igDummy(vec2(0.0f, 10.0f))
                igSeparator()
                igDummy(vec2(0.0f, 5.0f))

                let minTableHeight = max(igGetContentRegionAvail().y, 70.0f)
                if igBeginTable("##AgentList", 4, tableFlags, vec2(0.0f, minTableHeight), 0.0f):
                    igTableSetupColumn("Agent ID", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
                    igTableSetupColumn("Username", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
                    igTableSetupColumn("Process", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
                    igTableSetupColumn("Last seen", ImGuiTableColumnFlags_None.int32, 0.0f, 0)
                    igTableSetupScrollFreeze(0, 1)
                    igTableHeadersRow()

                    for agent in agents:
                        igTableNextRow(ImGuiTableRowFlags_None.int32, 0.0f)
                        if igTableSetColumnIndex(0):
                            if agent.elevated:
                                igPushStyleColor_Vec4(ImGui_Col_Text.cint, CONSOLE_ERROR)
                            igText(agent.agentId.cstring)
                            if agent.elevated:
                                igPopStyleColor(1)
                        if igTableSetColumnIndex(1):
                            igText(agent.username.cstring)
                        if igTableSetColumnIndex(2):
                            igText(fmt"{agent.pid}/{agent.process}".cstring)
                        if igTableSetColumnIndex(3):
                            let duration = now() - agent.latestCheckin.fromUnix().local()
                            let totalSeconds = duration.inSeconds

                            let hours = totalSeconds div 3600
                            let minutes = (totalSeconds mod 3600) div 60
                            let seconds = totalSeconds mod 60

                            let timeText = fmt"{hours:02d}:{minutes:02d}:{seconds:02d} ago"
                            if totalSeconds > agent.sleep:
                                igTextColored(CONSOLE_GRAY, timeText.cstring)
                            else:
                                igText(timeText.cstring)

                    igEndTable()

        igEndChild()
