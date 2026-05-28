import math, tables, strutils
import imguin/[cimgui, glfw_opengl, simple]
import ../../../types/client

const
    NODE_W* = 160.0f
    NODE_H* = 64.0f
    ZOOM_MIN* = 0.15f
    ZOOM_MAX* = 4.0f
    GRID_SIZE = 64.0f
    ARROW_LEN = 12.0f
    ARROW_WIDTH = 7.0f
    SERVER_NODE_ID* = "teamserver"

    COL_NODE_BG_NORMAL = 0xE0282828'u32
    COL_NODE_BG_ELEVATED = 0xE0101050'u32
    COL_NODE_BG_SERVER = 0xE0103010'u32
    COL_NODE_BORDER = 0xFF505050'u32
    COL_NODE_BORDER_ELEV = 0xFF2030E0'u32
    COL_NODE_BORDER_SRV = 0xFF30C030'u32
    COL_NODE_SEL_BORDER = 0xFFFFE040'u32
    COL_TEXT = 0xFFFFFFFF'u32
    COL_EDGE_HTTP = 0xFFA0A0A0'u32
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
proc hasNode*(w: GraphWidget, id: string): bool =
    w.nodes.hasKey(id)

proc addNode*(w: GraphWidget, id, label: string, elevated: bool = false) =
    if w.nodes.hasKey(id):
        return
    w.nodes[id] = GraphNode(
        pos: (x: 0.0f, y: 0.0f),
        label: label,
        elevated: elevated,
        selected: false
    )

proc removeNode*(w: GraphWidget, id: string) =
    w.nodes.del(id)

proc updateNode*(w: GraphWidget, id, label: string, elevated: bool) =
    if not w.nodes.hasKey(id):
        return
    let n = w.nodes[id]
    n.label = label
    n.elevated = elevated

proc clearEdges*(w: GraphWidget) =
    w.edges.setLen(0)

proc addEdge*(w: GraphWidget, srcId, dstId: string, edgeType: EdgeType) =
    w.edges.add(GraphEdge(srcId: srcId, dstId: dstId, edgeType: edgeType))

proc graphToScreen(wx, wy: float32, origin: ImVec2, w: GraphWidget): ImVec2 =
    ImVec2(x: origin.x + w.scrollOffset.x + wx * w.zoom, y: origin.y + w.scrollOffset.y + wy * w.zoom)

proc screenToGraph(sx, sy: float32, origin: ImVec2, w: GraphWidget): tuple[x, y: float32] =
    (x: (sx - origin.x - w.scrollOffset.x) / w.zoom, y: (sy - origin.y - w.scrollOffset.y) / w.zoom)

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
proc drawGrid(dl: ptr ImDrawList, origin, size: ImVec2, w: GraphWidget) =
    let step = GRID_SIZE * w.zoom
    let offX = w.scrollOffset.x mod step
    let offY = w.scrollOffset.y mod step

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

proc drawEdge(dl: ptr ImDrawList, edge: GraphEdge, origin: ImVec2, w: GraphWidget) =
    if not (w.nodes.hasKey(edge.srcId) and w.nodes.hasKey(edge.dstId)):
        return

    let src = w.nodes[edge.srcId]
    let dst = w.nodes[edge.dstId]

    let sc = graphToScreen(src.pos.x, src.pos.y, origin, w)
    let dc = graphToScreen(dst.pos.x, dst.pos.y, origin, w)

    let ex = dc.x - sc.x
    let ey = dc.y - sc.y
    let len = sqrt(ex * ex + ey * ey)
    if len < 0.001f: return

    let dx = ex / len
    let dy = ey / len

    let hw = NODE_W * 0.5f * w.zoom
    let hh = NODE_H * 0.5f * w.zoom

    let p1 = nodeAttach(sc.x, sc.y,  dx,  dy, hw, hh)
    let p2 = nodeAttach(dc.x, dc.y, -dx, -dy, hw, hh)

    let color = if edge.edgeType == EDGE_HTTP: COL_EDGE_HTTP else: COL_EDGE_SMB

    case edge.edgeType
    of EDGE_HTTP:
        dl.ImDrawList_AddLine(p1, p2, color, 1.5f)
    
    of EDGE_SMB:
        let 
            segLen = 8.0f
            gapLen = 5.0f
            edgeDx = p2.x - p1.x
            edgeDy = p2.y - p1.y
            edgeLen = sqrt(edgeDx * edgeDx + edgeDy * edgeDy)
            ndx = edgeDx / edgeLen
            ndy = edgeDy / edgeLen
        var t = 0.0f
        
        while t < edgeLen:
            let te = min(t + segLen, edgeLen)
            dl.ImDrawList_AddLine(
                ImVec2(x: p1.x + ndx * t, y: p1.y + ndy * t),
                ImVec2(x: p1.x + ndx * te, y: p1.y + ndy * te),
                color, 1.5f)
            t += segLen + gapLen

    drawArrow(dl, p2, dx, dy, color)

proc drawNode(dl: ptr ImDrawList, nodeId: string, node: GraphNode, origin: ImVec2, w: GraphWidget) =
    let isServer = nodeId == SERVER_NODE_ID
    let
        sc = graphToScreen(node.pos.x, node.pos.y, origin, w)
        hw = NODE_W * 0.5f * w.zoom
        hh = NODE_H * 0.5f * w.zoom
        p0 = ImVec2(x: sc.x - hw, y: sc.y - hh)
        p1 = ImVec2(x: sc.x + hw, y: sc.y + hh)
        rad = 6.0f * w.zoom

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

    if w.zoom > 0.35f:
        let parts = node.label.split('\t')
        if parts.len == 4:
            var line1Parts: seq[string]
            var line2Parts: seq[string]
            
            if w.showId: line1Parts.add(parts[0])
            if w.showProcess: line1Parts.add(parts[1])
            if w.showUser: line2Parts.add(parts[2])
            if w.showHostname: line2Parts.add(parts[3])
            
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

proc draw*(w: GraphWidget): string =
    let
        canvasPos = igGetCursorScreenPos()
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
            wb = screenToGraph(mx, my, canvasPos, w)
            newZoom = clamp(w.zoom * (1.0f + io.MouseWheel * 0.12f), ZOOM_MIN, ZOOM_MAX)
        
        w.scrollOffset.x = mx - canvasPos.x - wb.x * newZoom
        w.scrollOffset.y = my - canvasPos.y - wb.y * newZoom
        w.zoom = newZoom

    # Left-click: select node + start drag
    if canvasActive and igIsMouseClicked_Bool(ImGui_MouseButton_Left.int32, false):
        w.draggingNodeId = ""
        for nodeId, node in w.nodes:
            node.selected = false
        for nodeId, node in w.nodes:
            let 
                sc = graphToScreen(node.pos.x, node.pos.y, canvasPos, w)
                hw = NODE_W * 0.5f * w.zoom
                hh = NODE_H * 0.5f * w.zoom
            
            if io.MousePos.x >= sc.x - hw and io.MousePos.x <= sc.x + hw and
               io.MousePos.y >= sc.y - hh and io.MousePos.y <= sc.y + hh:
                w.draggingNodeId = nodeId
                if nodeId != SERVER_NODE_ID:
                    node.selected = true
                break

    # Right-click: select node + open context menu, or open config on empty canvas
    if canvasHovered and igIsMouseClicked_Bool(ImGui_MouseButton_Right.int32, false):
        var hitNode = false
        for nodeId, node in w.nodes:
            if nodeId == SERVER_NODE_ID: continue
            let sc = graphToScreen(node.pos.x, node.pos.y, canvasPos, w)
            let hw = NODE_W * 0.5f * w.zoom
            let hh = NODE_H * 0.5f * w.zoom
            if io.MousePos.x >= sc.x - hw and io.MousePos.x <= sc.x + hw and
               io.MousePos.y >= sc.y - hh and io.MousePos.y <= sc.y + hh:
                for _, n in w.nodes: n.selected = false
                node.selected = true
                igOpenPopup_str("GraphContextMenu", 0)
                hitNode = true
                break
    # Drag node
    if w.draggingNodeId != "" and igIsMouseDragging(ImGui_MouseButton_Left.int32, 1.0f):
        w.nodes[w.draggingNodeId].pos.x += io.MouseDelta.x / w.zoom
        w.nodes[w.draggingNodeId].pos.y += io.MouseDelta.y / w.zoom

    # Release
    if not igIsMouseDown_Nil(ImGui_MouseButton_Left.int32):
        w.draggingNodeId = ""

    # Drag on empty canvas to pan view
    if canvasActive and w.draggingNodeId == "" and igIsMouseDragging(ImGui_MouseButton_Left.int32, 1.0f):
        w.scrollOffset.x += io.MouseDelta.x
        w.scrollOffset.y += io.MouseDelta.y

    # Render
    dl.ImDrawList_PushClipRect(canvasPos, ImVec2(x: canvasPos.x + canvasSize.x, y: canvasPos.y + canvasSize.y), false)

    if w.showGrid:
        drawGrid(dl, canvasPos, canvasSize, w)
    for edge in w.edges:
        drawEdge(dl, edge, canvasPos, w)
    for nodeId, node in w.nodes:
        drawNode(dl, nodeId, node, canvasPos, w)

    dl.ImDrawList_PopClipRect()

    let overlayPos = ImVec2(x: canvasPos.x + canvasSize.x - 8.0f, y: canvasPos.y + 8.0f)
    igSetNextWindowPos(overlayPos, ImGuiCond_Always.int32, ImVec2(x: 1.0f, y: 0.0f))
    igSetNextWindowBgAlpha(0.7f)
    let overlayFlags = ImGuiWindowFlags_NoMove.int32 or ImGuiWindowFlags_NoResize.int32 or ImGuiWindowFlags_NoTitleBar.int32 or ImGuiWindowFlags_AlwaysAutoResize.int32 or ImGuiWindowFlags_NoSavedSettings.int32 or ImGuiWindowFlags_NoFocusOnAppearing.int32 or ImGuiWindowFlags_NoDocking.int32
    if igBegin("##GraphSettings", nil, overlayFlags):
        igText("Graph Settings:")
        discard igCheckbox("Grid", addr w.showGrid)
        igSeparator()
        discard igCheckbox("Agent ID", addr w.showId)
        discard igCheckbox("Process", addr w.showProcess)
        discard igCheckbox("Username", addr w.showUser)
        discard igCheckbox("Hostname", addr w.showHostname)
    igEnd()

    for nodeId, node in w.nodes:
        if node.selected: return nodeId
    return ""

#[
    Layout
]#
proc applyLayout*(w: GraphWidget) =
    # Find server root
    var root = ""
    for nodeId in w.nodes.keys:
        if nodeId == SERVER_NODE_ID:
            root = nodeId
            break
    if root == "": return

    # Build undirected adjacency from edges
    var adj = initTable[string, seq[string]]()
    for nodeId in w.nodes.keys:
        adj[nodeId] = @[]
    for edge in w.edges:
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
    for nodeId in w.nodes.keys:
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
            w.nodes[nodeId].pos = (
                x: float32(l) * LAYER_SPACING,
                y: (float32(i) - float32(n - 1) * 0.5f) * NODE_SPACING)
