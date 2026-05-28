import math, tables, strutils
import imguin/[cimgui, glfw_opengl, simple]
import ../../../types/[common, client]

const
    NODE_W* = 160.0f
    NODE_H* = 64.0f
    ZOOM_MIN* = 0.15f
    ZOOM_MAX* = 4.0f
    GRID_SIZE = 64.0f
    ARROW_LEN = 12.0f
    ARROW_WIDTH = 7.0f
    SERVER_NODE_ID = "teamserver"

    COL_NODE_BG_NORMAL = 0xE0282828'u32
    COL_NODE_BG_ELEVATED = 0xE0101050'u32
    COL_NODE_BG_SERVER = 0xE0103010'u32
    COL_NODE_BORDER = 0xFF505050'u32
    COL_NODE_BORDER_ELEV = 0xFF2030E0'u32
    COL_NODE_BORDER_SRV = 0xFF30C030'u32
    COL_NODE_SEL_BORDER = 0xFFFFE040'u32
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
        showGrid: true,
        showId: true,
        showProcess: true,
        showUser: true,
        showHostname: true
    )

#[
    Nodes & Edges
]#
proc hasNode(graph: GraphWidget, id: string): bool =
    graph.nodes.hasKey(id)

proc addNode(graph: GraphWidget, id, label: string, elevated: bool = false) =
    if graph.nodes.hasKey(id):
        return
    graph.nodes[id] = GraphNode(
        pos: (x: 0.0f, y: 0.0f),
        label: label,
        elevated: elevated,
        selected: false
    )

proc removeNode(graph: GraphWidget, id: string) =
    graph.nodes.del(id)

proc updateNode(graph: GraphWidget, id, label: string, elevated: bool) =
    if not graph.nodes.hasKey(id):
        return
    let n = graph.nodes[id]
    n.label = label
    n.elevated = elevated

proc clearEdges(graph: GraphWidget) =
    graph.edges.setLen(0)

proc addEdge(graph: GraphWidget, srcId, dstId: string, edgeType: EdgeType) =
    graph.edges.add(GraphEdge(srcId: srcId, dstId: dstId, edgeType: edgeType))

proc graphToScreen(wx, wy: float32, origin: ImVec2, graph: GraphWidget): ImVec2 =
    ImVec2(x: origin.x + graph.scrollOffset.x + wx * graph.zoom, y: origin.y + graph.scrollOffset.y + wy * graph.zoom)

proc screenToGraph(sx, sy: float32, origin: ImVec2, graph: GraphWidget): tuple[x, y: float32] =
    (x: (sx - origin.x - graph.scrollOffset.x) / graph.zoom, y: (sy - origin.y - graph.scrollOffset.y) / graph.zoom)

proc nodeAttach(cx, cy, dx, dy, halfW, halfH: float32): ImVec2 =
    var tx = 1e9f
    var ty = 1e9f
    if abs(dx) > 0.0001f: tx = halfW / abs(dx)
    if abs(dy) > 0.0001f: ty = halfH / abs(dy)
    let t = min(tx, ty)
    ImVec2(x: cx + dx * t, y: cy + dy * t)

#[
    Drawing
]#
proc drawGrid(dl: ptr ImDrawList, origin, size: ImVec2, graph: GraphWidget) =
    let step = GRID_SIZE * graph.zoom
    let offX = graph.scrollOffset.x mod step
    let offY = graph.scrollOffset.y mod step

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

proc drawEdge(dl: ptr ImDrawList, edge: GraphEdge, origin: ImVec2, graph: GraphWidget) =
    if not (graph.nodes.hasKey(edge.srcId) and graph.nodes.hasKey(edge.dstId)):
        return

    let src = graph.nodes[edge.srcId]
    let dst = graph.nodes[edge.dstId]

    let sc = graphToScreen(src.pos.x, src.pos.y, origin, graph)
    let dc = graphToScreen(dst.pos.x, dst.pos.y, origin, graph)

    let ex = dc.x - sc.x
    let ey = dc.y - sc.y
    let len = sqrt(ex * ex + ey * ey)
    if len < 0.001f: return

    let dx = ex / len
    let dy = ey / len

    let hw = NODE_W * 0.5f * graph.zoom
    let hh = NODE_H * 0.5f * graph.zoom

    let p1 = nodeAttach(sc.x, sc.y, dx, dy, hw, hh)
    let p2 = nodeAttach(dc.x, dc.y, -dx, -dy, hw, hh)

    let color = if edge.edgeType == EDGE_HTTP: COL_EDGE_HTTP else: COL_EDGE_SMB

    let 
        label = $edge.edgeType
        showLabel = graph.zoom > 0.5f
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

proc drawNode(dl: ptr ImDrawList, nodeId: string, node: GraphNode, origin: ImVec2, graph: GraphWidget) =
    let isServer = nodeId == SERVER_NODE_ID
    let
        sc = graphToScreen(node.pos.x, node.pos.y, origin, graph)
        hw = NODE_W * 0.5f * graph.zoom
        hh = NODE_H * 0.5f * graph.zoom
        p0 = ImVec2(x: sc.x - hw, y: sc.y - hh)
        p1 = ImVec2(x: sc.x + hw, y: sc.y + hh)
        rad = 6.0f * graph.zoom

    let bgColor =
        if isServer: COL_NODE_BG_SERVER
        elif node.elevated: COL_NODE_BG_ELEVATED
        else: COL_NODE_BG_NORMAL

    let borderColor =
        if isServer: COL_NODE_BORDER_SRV
        elif node.elevated: COL_NODE_BORDER_ELEV
        else: COL_NODE_BORDER

    dl.ImDrawList_AddRectFilled(p0, p1, bgColor, rad, 0)

    if node.selected:
        dl.ImDrawList_AddRect(ImVec2(x: p0.x - 2.0f, y: p0.y - 2.0f), ImVec2(x: p1.x + 2.0f, y: p1.y + 2.0f), COL_NODE_SEL_BORDER, rad + 2.0f, 0, 2.5f)
    dl.ImDrawList_AddRect(p0, p1, borderColor, rad, 0, 1.5f)

    if graph.zoom > 0.35f:
        let parts = node.label.split('\t')
        if parts.len == 4:
            var line1Parts: seq[string]
            var line2Parts: seq[string]
            
            if graph.showId: line1Parts.add(parts[0])
            if graph.showProcess: line1Parts.add(parts[1])
            if graph.showUser: line2Parts.add(parts[2])
            if graph.showHostname: line2Parts.add(parts[3])
            
            let 
                line1 = line1Parts.join(" | ")
                line2 = if line2Parts.len > 0: line2Parts.join(" @ ") else: ""
                fontSize = igGetFontSize()
            
            if line1.len > 0 and line2.len > 0:
                let 
                    totalH = fontSize * 2.0f + 3.0f
                    ly1 = sc.y - totalH * 0.5f
                    ly2 = ly1 + fontSize + 3.0f
                    sz1 = igCalcTextSize(line1.cstring, nil, false, -1.0f)
                    sz2 = igCalcTextSize(line2.cstring, nil, false, -1.0f)
                dl.ImDrawList_AddText_Vec2(ImVec2(x: sc.x - sz1.x * 0.5f, y: ly1), COL_TEXT, line1.cstring, nil)
                dl.ImDrawList_AddText_Vec2(ImVec2(x: sc.x - sz2.x * 0.5f, y: ly2), COL_TEXT, line2.cstring, nil)
            elif line1.len > 0:
                let sz = igCalcTextSize(line1.cstring, nil, false, -1.0f)
                dl.ImDrawList_AddText_Vec2(ImVec2(x: sc.x - sz.x * 0.5f, y: sc.y - sz.y * 0.5f), COL_TEXT, line1.cstring, nil)
            elif line2.len > 0:
                let sz = igCalcTextSize(line2.cstring, nil, false, -1.0f)
                dl.ImDrawList_AddText_Vec2(ImVec2(x: sc.x - sz.x * 0.5f, y: sc.y - sz.y * 0.5f), COL_TEXT, line2.cstring, nil)
        else:
            let labelSz = igCalcTextSize(node.label.cstring, nil, false, -1.0f)
            dl.ImDrawList_AddText_Vec2(ImVec2(x: sc.x - labelSz.x * 0.5f, y: sc.y - labelSz.y * 0.5f), COL_TEXT, node.label.cstring, nil)

proc applyLayout(graph: GraphWidget) =
    # Find server root
    var root = ""
    for nodeId in graph.nodes.keys:
        if nodeId == SERVER_NODE_ID:
            root = nodeId
            break
    if root == "": return

    # Build undirected adjacency from edges
    var adj = initTable[string, seq[string]]()
    for nodeId in graph.nodes.keys:
        adj[nodeId] = @[]
    for edge in graph.edges:
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
    for nodeId in graph.nodes.keys:
        if not level.hasKey(nodeId):
            inc maxLevel
            level[nodeId] = maxLevel

    # Group nodes by level
    var levels = initTable[int, seq[string]]()
    for nodeId, l in level:
        levels.mgetOrPut(l, @[]).add(nodeId)

    const LAYER_SPACING = 280.0f
    const NODE_SPACING = 110.0f

    for l, ids in levels:
        let n = ids.len
        for i, nodeId in ids:
            graph.nodes[nodeId].pos = (
                x: float32(l) * LAYER_SPACING,
                y: (float32(i) - float32(n - 1) * 0.5f) * NODE_SPACING)

proc update(graph: GraphWidget, agents: Table[string, UIAgent], listeners: Table[string, UIListener]) =
    var layoutChanged = false

    if not graph.hasNode(SERVER_NODE_ID):
        graph.addNode(SERVER_NODE_ID, "Team Server")
        layoutChanged = true

    for agentId, agent in agents:
        let label = agent.agentId & "\t" & $agent.pid & "/" & agent.process & "\t" & agent.username & "\t" & agent.hostname
        if graph.hasNode(agentId):
            graph.updateNode(agentId, label, agent.elevated)
        else:
            graph.addNode(agentId, label, elevated = agent.elevated)
            layoutChanged = true

    var toRemove: seq[string]
    for nodeId in graph.nodes.keys:
        if nodeId != SERVER_NODE_ID and not agents.hasKey(nodeId):
            toRemove.add(nodeId)
    for id in toRemove:
        graph.removeNode(id)
        layoutChanged = true

    graph.clearEdges()
    for agentId, agent in agents:
        if agent.parentId != "" and agents.hasKey(agent.parentId):
            let edgeType = 
                if listeners.hasKey(agent.listenerId):
                    case listeners[agent.listenerId].listenerType
                    of LISTENER_HTTP: EDGE_HTTP
                    of LISTENER_SMB: EDGE_SMB
                else: 
                    EDGE_HTTP
            graph.addEdge(agent.parentId, agentId, edgeType)
        else:
            graph.addEdge(agentId, SERVER_NODE_ID, EDGE_HTTP)

    if layoutChanged:
        graph.applyLayout()

proc draw*(graph: GraphWidget, agents: Table[string, UIAgent], listeners: Table[string, UIListener]): string =
    graph.update(agents, listeners)
    let
        canvasPos = igGetCursorScreenPos()
        canvasLocalPos = igGetCursorPos()
        canvasSize = igGetContentRegionAvail()
    if canvasSize.x < 50.0f or canvasSize.y < 50.0f:
        return ""

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
            wb = screenToGraph(mx, my, canvasPos, graph)
            newZoom = clamp(graph.zoom * (1.0f + io.MouseWheel * 0.12f), ZOOM_MIN, ZOOM_MAX)
        graph.scrollOffset.x = mx - canvasPos.x - wb.x * newZoom
        graph.scrollOffset.y = my - canvasPos.y - wb.y * newZoom
        graph.zoom = newZoom

    # Left-click on node to select
    if canvasActive and igIsMouseClicked_Bool(ImGui_MouseButton_Left.int32, false):
        graph.draggingNodeId = ""
        for nodeId, node in graph.nodes:
            node.selected = false
        for nodeId, node in graph.nodes:
            let
                sc = graphToScreen(node.pos.x, node.pos.y, canvasPos, graph)
                hw = NODE_W * 0.5f * graph.zoom
                hh = NODE_H * 0.5f * graph.zoom
            if io.MousePos.x >= sc.x - hw and io.MousePos.x <= sc.x + hw and
               io.MousePos.y >= sc.y - hh and io.MousePos.y <= sc.y + hh:
                graph.draggingNodeId = nodeId
                if nodeId != SERVER_NODE_ID:
                    node.selected = true
                break

    # Right-click on node to open context menu
    if canvasHovered and igIsMouseClicked_Bool(ImGui_MouseButton_Right.int32, false):
        for nodeId, node in graph.nodes:
            if nodeId == SERVER_NODE_ID: continue
            let
                sc = graphToScreen(node.pos.x, node.pos.y, canvasPos, graph)
                hw = NODE_W * 0.5f * graph.zoom
                hh = NODE_H * 0.5f * graph.zoom
            if io.MousePos.x >= sc.x - hw and io.MousePos.x <= sc.x + hw and
               io.MousePos.y >= sc.y - hh and io.MousePos.y <= sc.y + hh:
                for _, n in graph.nodes: n.selected = false
                node.selected = true
                igOpenPopup_str("GraphContextMenu", 0)
                break

    # Drag node
    if graph.draggingNodeId != "" and igIsMouseDragging(ImGui_MouseButton_Left.int32, 1.0f):
        graph.nodes[graph.draggingNodeId].pos.x += io.MouseDelta.x / graph.zoom
        graph.nodes[graph.draggingNodeId].pos.y += io.MouseDelta.y / graph.zoom

    # Release
    if not igIsMouseDown_Nil(ImGui_MouseButton_Left.int32):
        graph.draggingNodeId = ""

    # Drag on empty canvas to pan view
    if canvasActive and graph.draggingNodeId == "" and igIsMouseDragging(ImGui_MouseButton_Left.int32, 1.0f):
        graph.scrollOffset.x += io.MouseDelta.x
        graph.scrollOffset.y += io.MouseDelta.y

    # Render
    dl.ImDrawList_PushClipRect(canvasPos, ImVec2(x: canvasPos.x + canvasSize.x, y: canvasPos.y + canvasSize.y), false)

    if graph.showGrid:
        drawGrid(dl, canvasPos, canvasSize, graph)
    for edge in graph.edges:
        drawEdge(dl, edge, canvasPos, graph)
    for nodeId, node in graph.nodes:
        drawNode(dl, nodeId, node, canvasPos, graph)

    dl.ImDrawList_PopClipRect()

    let settingsWidth = 160.0f
    let settingsHeight = 190.0f
    igSetCursorPos(ImVec2(x: canvasLocalPos.x + canvasSize.x - settingsWidth - 8.0f, y: canvasLocalPos.y + 8.0f))
    igPushStyleColor_Vec4(ImGui_Col_ChildBg.cint, igGetStyleColorVec4(ImGuiCol(ImGui_Col_PopupBg.int32))[])
    if igBeginChild("##GraphSettings", ImVec2(x: settingsWidth, y: settingsHeight), true, 0):
        igText("Graph Settings:")
        discard igCheckbox("Grid", addr graph.showGrid)
        igSeparator()
        discard igCheckbox("Agent ID", addr graph.showId)
        discard igCheckbox("Process", addr graph.showProcess)
        discard igCheckbox("Username", addr graph.showUser)
        discard igCheckbox("Hostname", addr graph.showHostname)
    igEndChild()
    igPopStyleColor(1)

    for nodeId, node in graph.nodes:
        if node.selected: return nodeId
    return ""
