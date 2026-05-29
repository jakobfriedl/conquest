import math, tables, strutils
import imguin/[cimgui, glfw_opengl, simple]
import ../../../types/[common, client]
import ../../utils/[loadImage, globals]

const
    NODE_ICON_SIZE = 48.0f
    ZOOM_MIN* = 0.15f
    ZOOM_MAX* = 4.0f
    GRID_SIZE = 64.0f
    ARROW_LEN = 12.0f
    ARROW_WIDTH = 7.0f
    SERVER_NODE_ID = "teamserver"

    COL_TEXT = 0xFFFFFFFF'u32
    COL_EDGE_HTTP = 0xFF4488FF'u32
    COL_EDGE_SMB = 0xFF60C0FF'u32
    COL_CANVAS_BG = 0xFF1E1E1E'u32
    COL_GRID = 0x18FFFFFF'u32

proc Graph*(): GraphWidget =
    result = GraphWidget(
        nodes: initTable[string, GraphNode](),
        edges: @[],
        scrollOffset: (x: 80.0f, y: 200.0f),
        zoom: 1.0f,
        draggingNodeId: "",
        showGrid: false,
        showId: true,
        showProcess: false,
        showUser: true,
        showHostname: true
    )

#[
    Nodes & Edges
]#
proc hasNode(component: GraphWidget, id: string): bool =
    component.nodes.hasKey(id)

proc addNode(component: GraphWidget, id, label: string, elevated: bool = false) =
    if component.nodes.hasKey(id):
        return
    component.nodes[id] = GraphNode(
        pos: (x: 0.0f, y: 0.0f),
        label: label,
        elevated: elevated,
        selected: false
    )

proc removeNode(component: GraphWidget, id: string) =
    component.nodes.del(id)

proc updateNode(component: GraphWidget, id, label: string, elevated: bool) =
    if not component.nodes.hasKey(id):
        return
    let n = component.nodes[id]
    n.label = label
    n.elevated = elevated

proc clearEdges(component: GraphWidget) =
    component.edges.setLen(0)

proc addEdge(component: GraphWidget, srcId, dstId: string, edgeType: EdgeType) =
    component.edges.add(GraphEdge(srcId: srcId, dstId: dstId, edgeType: edgeType))

proc graphToScreen(wx, wy: float32, origin: ImVec2, component: GraphWidget): ImVec2 =
    ImVec2(x: origin.x + component.scrollOffset.x + wx * component.zoom, y: origin.y + component.scrollOffset.y + wy * component.zoom)

proc screenToGraph(sx, sy: float32, origin: ImVec2, component: GraphWidget): tuple[x, y: float32] =
    (x: (sx - origin.x - component.scrollOffset.x) / component.zoom, y: (sy - origin.y - component.scrollOffset.y) / component.zoom)

proc nodeAttach(cx, cy, dx, dy, r: float32): ImVec2 =
    ImVec2(x: cx + dx * r, y: cy + dy * r)

#[
    Drawing
]#
proc drawGrid(dl: ptr ImDrawList, origin, size: ImVec2, component: GraphWidget) =
    let step = GRID_SIZE * component.zoom
    let offX = component.scrollOffset.x mod step
    let offY = component.scrollOffset.y mod step

    var x = offX
    while x < size.x:
        dl.ImDrawList_AddLine(ImVec2(x: origin.x + x, y: origin.y), ImVec2(x: origin.x + x, y: origin.y + size.y), COL_GRID, 1.0f)
        x += step

    var y = offY
    while y < size.y:
        dl.ImDrawList_AddLine(ImVec2(x: origin.x, y: origin.y + y), ImVec2(x: origin.x + size.x, y: origin.y + y), COL_GRID, 1.0f)
        y += step

proc drawArrow(dl: ptr ImDrawList, tip: ImVec2, dx, dy: float32, color: uint32) =
    let
        px = -dy
        py = dx
        bx = tip.x - dx * ARROW_LEN
        by = tip.y - dy * ARROW_LEN
    
    dl.ImDrawList_AddTriangleFilled(
        tip,
        ImVec2(x: bx + px * ARROW_WIDTH, y: by + py * ARROW_WIDTH),
        ImVec2(x: bx - px * ARROW_WIDTH, y: by - py * ARROW_WIDTH),
        color)

proc drawEdge(dl: ptr ImDrawList, edge: GraphEdge, origin: ImVec2, component: GraphWidget) =
    if not (component.nodes.hasKey(edge.srcId) and component.nodes.hasKey(edge.dstId)):
        return

    let src = component.nodes[edge.srcId]
    let dst = component.nodes[edge.dstId]

    let sc = graphToScreen(src.pos.x, src.pos.y, origin, component)
    let dc = graphToScreen(dst.pos.x, dst.pos.y, origin, component)

    let ex = dc.x - sc.x
    let ey = dc.y - sc.y
    let len = sqrt(ex * ex + ey * ey)
    if len < 0.001f: return

    let dx = ex / len
    let dy = ey / len

    let r = NODE_ICON_SIZE * 0.5f * component.zoom
    let p1 = nodeAttach(sc.x, sc.y, dx, dy, r)
    let p2 = nodeAttach(dc.x, dc.y, -dx, -dy, r)

    let color = if edge.edgeType == EDGE_HTTP: COL_EDGE_HTTP else: COL_EDGE_SMB

    let 
        label = $edge.edgeType
        showLabel = component.zoom > 0.5f
        sz = if showLabel: igCalcTextSize(label.cstring, nil, false, -1.0f) else: ImVec2(x: 0.0f, y: 0.0f)
        edgePLen = sqrt((p2.x - p1.x) * (p2.x - p1.x) + (p2.y - p1.y) * (p2.y - p1.y))
        halfGap = min(if showLabel: sz.x * 0.5f + 4.0f else: 0.0f, edgePLen * 0.4f)
        mx = (p1.x + p2.x) * 0.5f
        my = (p1.y + p2.y) * 0.5f
        gapA = ImVec2(x: mx - dx * halfGap, y: my - dy * halfGap)
        gapB = ImVec2(x: mx + dx * halfGap, y: my + dy * halfGap)

    case edge.edgeType
    of EDGE_HTTP:
        dl.ImDrawList_AddLine(p1, gapA, color, 1.5f)
        dl.ImDrawList_AddLine(gapB, p2, color, 1.5f)

    of EDGE_SMB:
        let segLen = 8.0f
        let gapLen = 5.0f
        for (segA, segB) in @[(p1, gapA), (gapB, p2)]:
            let sdx = segB.x - segA.x
            let sdy = segB.y - segA.y
            let sLen = sqrt(sdx * sdx + sdy * sdy)
            if sLen < 0.001f: continue
            let ndx = sdx / sLen
            let ndy = sdy / sLen
            var t = 0.0f
            while t < sLen:
                let te = min(t + segLen, sLen)
                dl.ImDrawList_AddLine(
                    ImVec2(x: segA.x + ndx * t, y: segA.y + ndy * t),
                    ImVec2(x: segA.x + ndx * te, y: segA.y + ndy * te),
                    color, 1.5f)
                t += segLen + gapLen

    drawArrow(dl, p2, dx, dy, color)

    if showLabel:
        dl.ImDrawList_AddText_Vec2(ImVec2(x: mx - sz.x * 0.5f, y: my - sz.y * 0.5f), color, label.cstring, nil)

proc drawNode(dl: ptr ImDrawList, nodeId: string, node: GraphNode, origin: ImVec2, component: GraphWidget) =
    let sc = graphToScreen(node.pos.x, node.pos.y, origin, component)
    let half = NODE_ICON_SIZE * 0.5f * component.zoom

    let p0 = ImVec2(x: sc.x - half, y: sc.y - half)
    let p1 = ImVec2(x: sc.x + half, y: sc.y + half)
    if component.texture != 0:
        let texRef = ImTextureRef_c(internal_TexData: nil, internal_TexID: ImTextureID(component.texture))
        dl.ImDrawList_AddImage(texRef, p0, p1, ImVec2(x: 0.0f, y: 0.0f), ImVec2(x: 1.0f, y: 1.0f), 0xFFFFFFFF'u32)

    if component.zoom > 0.35f:
        let parts = node.label.split('\t')
        if parts.len == 4:
            var line1Parts: seq[string]
            var line2Parts: seq[string]
            if component.showId: line1Parts.add(parts[0])
            if component.showProcess: line1Parts.add(parts[1])
            if component.showUser: line2Parts.add(parts[2])
            if component.showHostname: line2Parts.add(parts[3])
            let line1 = line1Parts.join(" | ")
            let line2 = if line2Parts.len > 0: line2Parts.join(" @ ") else: ""
            let baseY = sc.y + half + 4.0f
            let fontSize = igGetFontSize()
            if line1.len > 0:
                let sz = igCalcTextSize(line1.cstring, nil, false, -1.0f)
                dl.ImDrawList_AddText_Vec2(ImVec2(x: sc.x - sz.x * 0.5f, y: baseY), COL_TEXT, line1.cstring, nil)
            if line2.len > 0:
                let line2Y = if line1.len > 0: baseY + fontSize + 2.0f else: baseY
                let sz = igCalcTextSize(line2.cstring, nil, false, -1.0f)
                dl.ImDrawList_AddText_Vec2(ImVec2(x: sc.x - sz.x * 0.5f, y: line2Y), COL_TEXT, line2.cstring, nil)
        else:
            let sz = igCalcTextSize(node.label.cstring, nil, false, -1.0f)
            dl.ImDrawList_AddText_Vec2(ImVec2(x: sc.x - sz.x * 0.5f, y: sc.y + half + 4.0f), COL_TEXT, node.label.cstring, nil)

proc applyLayout(component: GraphWidget) =
    # Find server root node
    var root = ""
    for nodeId in component.nodes.keys:
        if nodeId == SERVER_NODE_ID:
            root = nodeId
            break
    if root == "": return

    # Build undirected adjacency from edges
    var adj = initTable[string, seq[string]]()
    for nodeId in component.nodes.keys:
        adj[nodeId] = @[]
    for edge in component.edges:
        if adj.hasKey(edge.srcId): adj[edge.srcId].add(edge.dstId)
        if adj.hasKey(edge.dstId): adj[edge.dstId].add(edge.srcId)

    # BFS to assign depth levels from root
    var level = initTable[string, int]()
    var queue: seq[string] = @[root]
    level[root] = 0
    while queue.len > 0:
        let curr = queue[0]
        queue.delete(0)
        for nb in adj.getOrDefault(curr, @[]):
            if not level.hasKey(nb):
                level[nb] = level[curr] + 1
                queue.add(nb)

    # Unreachable nodes go one level past the deepest reachable
    var maxLevel = 0
    for _, l in level: maxLevel = max(maxLevel, l)
    for nodeId in component.nodes.keys:
        if not level.hasKey(nodeId):
            inc maxLevel
            level[nodeId] = maxLevel

    # Group nodes by level
    var levels = initTable[int, seq[string]]()
    for nodeId, l in level:
        levels.mgetOrPut(l, @[]).add(nodeId)

    const LAYER_SPACING = 280.0f
    const NODE_SPACING = 120.0f

    for l, ids in levels:
        let n = ids.len
        for i, nodeId in ids:
            component.nodes[nodeId].pos = (
                x: float32(l) * LAYER_SPACING,
                y: (float32(i) - float32(n - 1) * 0.5f) * NODE_SPACING)

proc update(component: GraphWidget, agents: Table[string, UIAgent], listeners: Table[string, UIListener]) =
    var layoutChanged = false

    if not component.hasNode(SERVER_NODE_ID):
        component.addNode(SERVER_NODE_ID, "Team Server")
        layoutChanged = true

    for agentId, agent in agents:
        let label = agent.agentId & "\t" & $agent.pid & "/" & agent.process & "\t" & agent.username & "\t" & agent.hostname
        if component.hasNode(agentId):
            component.updateNode(agentId, label, agent.elevated)
        else:
            component.addNode(agentId, label, elevated = agent.elevated)
            layoutChanged = true

    var toRemove: seq[string]
    for nodeId in component.nodes.keys:
        if nodeId != SERVER_NODE_ID and not agents.hasKey(nodeId):
            toRemove.add(nodeId)
    for id in toRemove:
        component.removeNode(id)
        layoutChanged = true

    component.clearEdges()
    for agentId, agent in agents:
        if agent.parentId != "" and agents.hasKey(agent.parentId):
            let edgeType = 
                if listeners.hasKey(agent.listenerId):
                    case listeners[agent.listenerId].listenerType
                    of LISTENER_HTTP: EDGE_HTTP
                    of LISTENER_SMB: EDGE_SMB
                else: 
                    EDGE_HTTP
            component.addEdge(agent.parentId, agentId, edgeType)
        else:
            component.addEdge(agentId, SERVER_NODE_ID, EDGE_HTTP)

    if layoutChanged:
        component.applyLayout()

proc draw*(component: GraphWidget, agents: Table[string, UIAgent], listeners: Table[string, UIListener]): tuple[selectedId: string, openConsoleId: string] =
    component.update(agents, listeners)

    if not component.loaded:
        component.loaded = true
        var w, h: int
        discard loadTextureFromFile(CONQUEST_ROOT & "/src/client/resources/icon.png", component.texture, w, h)

    let
        canvasPos = igGetCursorScreenPos()
        canvasLocalPos = igGetCursorPos()
        canvasSize = igGetContentRegionAvail()
    if canvasSize.x < 50.0f or canvasSize.y < 50.0f:
        return ("", "")

    let dl = igGetWindowDrawList()
    dl.ImDrawList_AddRectFilled(canvasPos, ImVec2(x: canvasPos.x + canvasSize.x, y: canvasPos.y + canvasSize.y), COL_CANVAS_BG, 0, 0)

    discard igInvisibleButton("##Canvas", canvasSize, 0)
    let canvasActive = igIsItemActive()
    let canvasHovered = igIsItemHovered(0)

    let io = igGetIO()

    # Zoom toward cursor
    if canvasHovered and io.MouseWheel != 0.0f:
        let
            mx = io.MousePos.x
            my = io.MousePos.y
            wb = screenToGraph(mx, my, canvasPos, component)
            newZoom = clamp(component.zoom * (1.0f + io.MouseWheel * 0.12f), ZOOM_MIN, ZOOM_MAX)
        component.scrollOffset.x = mx - canvasPos.x - wb.x * newZoom
        component.scrollOffset.y = my - canvasPos.y - wb.y * newZoom
        component.zoom = newZoom

    # Deselect when clicking outside the canvas
    if not canvasActive and igIsMouseClicked_Bool(ImGui_MouseButton_Left.int32, false):
        for nodeId, node in component.nodes:
            node.selected = false

    # Left-click on node to select
    if canvasActive and igIsMouseClicked_Bool(ImGui_MouseButton_Left.int32, false):
        component.draggingNodeId = ""
        for nodeId, node in component.nodes:
            node.selected = false
        let r = NODE_ICON_SIZE * 0.5f * component.zoom
        for nodeId, node in component.nodes:
            let sc = graphToScreen(node.pos.x, node.pos.y, canvasPos, component)
            let mdx = io.MousePos.x - sc.x
            let mdy = io.MousePos.y - sc.y
            if sqrt(mdx * mdx + mdy * mdy) < r:
                component.draggingNodeId = nodeId
                if nodeId != SERVER_NODE_ID:
                    node.selected = true
                break

    # Right-click on node to open context menu
    if canvasHovered and igIsMouseClicked_Bool(ImGui_MouseButton_Right.int32, false):
        let r = NODE_ICON_SIZE * 0.5f * component.zoom
        for nodeId, node in component.nodes:
            if nodeId == SERVER_NODE_ID: continue
            let sc = graphToScreen(node.pos.x, node.pos.y, canvasPos, component)
            let mdx = io.MousePos.x - sc.x
            let mdy = io.MousePos.y - sc.y
            if sqrt(mdx * mdx + mdy * mdy) < r:
                for _, n in component.nodes: n.selected = false
                node.selected = true
                igOpenPopup_str("GraphContextMenu", 0)
                break

    # Drag node
    if component.draggingNodeId != "" and igIsMouseDragging(ImGui_MouseButton_Left.int32, 1.0f):
        component.nodes[component.draggingNodeId].pos.x += io.MouseDelta.x / component.zoom
        component.nodes[component.draggingNodeId].pos.y += io.MouseDelta.y / component.zoom

    # Release
    if not igIsMouseDown_Nil(ImGui_MouseButton_Left.int32):
        component.draggingNodeId = ""

    # Drag on empty canvas to pan view
    if canvasActive and component.draggingNodeId == "" and igIsMouseDragging(ImGui_MouseButton_Left.int32, 1.0f):
        component.scrollOffset.x += io.MouseDelta.x
        component.scrollOffset.y += io.MouseDelta.y

    # Render
    dl.ImDrawList_PushClipRect(canvasPos, ImVec2(x: canvasPos.x + canvasSize.x, y: canvasPos.y + canvasSize.y), false)

    if component.showGrid:
        drawGrid(dl, canvasPos, canvasSize, component)
    for edge in component.edges:
        drawEdge(dl, edge, canvasPos, component)
    for nodeId, node in component.nodes:
        drawNode(dl, nodeId, node, canvasPos, component)

    dl.ImDrawList_PopClipRect()

    let settingsWidth = 180.0f
    igSetCursorPos(ImVec2(x: canvasLocalPos.x + canvasSize.x - settingsWidth - 8.0f, y: canvasLocalPos.y + 8.0f))
    igPushStyleColor_Vec4(ImGui_Col_ChildBg.cint, igGetStyleColorVec4(ImGuiCol(ImGui_Col_PopupBg.int32))[])
    if igBeginChild_Str("##GraphSettings", ImVec2(x: settingsWidth, y: 0.0f), ImGui_ChildFlags_Borders.int32 or ImGui_ChildFlags_AutoResizeY.int32, 0):
        if igTreeNodeEx_Str("Graph Settings", ImGuiTreeNodeFlags_DefaultOpen.int32):
            discard igCheckbox("Grid", addr component.showGrid)
            igSeparator()
            discard igCheckbox("Agent ID", addr component.showId)
            discard igCheckbox("Process", addr component.showProcess)
            discard igCheckbox("Username", addr component.showUser)
            discard igCheckbox("Hostname", addr component.showHostname)
            igTreePop()
    igEndChild()
    igPopStyleColor(1)

    var openConsoleId = ""
    if canvasActive and igIsMouseDoubleClicked_Nil(ImGui_MouseButton_Left.int32):
        let r = NODE_ICON_SIZE * 0.5f * component.zoom
        for nodeId, node in component.nodes:
            if nodeId == SERVER_NODE_ID: continue
            let sc = graphToScreen(node.pos.x, node.pos.y, canvasPos, component)
            let mdx = io.MousePos.x - sc.x
            let mdy = io.MousePos.y - sc.y
            if sqrt(mdx * mdx + mdy * mdy) < r:
                openConsoleId = nodeId
                break

    var selectedId = ""
    for nodeId, node in component.nodes:
        if node.selected:
            selectedId = nodeId
            break
    return (selectedId: selectedId, openConsoleId: openConsoleId)
