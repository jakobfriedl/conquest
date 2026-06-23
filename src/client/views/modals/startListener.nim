import strutils, strformat, base64
import imguin/[cimgui, glfw_opengl]
import ../widgets/textarea
import ../../utils/[appImGui, utils, globals, dialogs]
import ../../../common/[utils, profile]
import ../../../common/toml/toml
import ../../../types/[common, client]

const
    DEFAULT_PORT = 8080'u16
    PLACEHOLDER = "PLACEHOLDER"

proc ListenerModal*(): ListenerModalComponent =
    result = new ListenerModalComponent
    zeroMem(addr result.callbackHosts[0], 256 * 32)
    zeroMem(addr result.bindAddress[0], 256)
    result.bindPort = DEFAULT_PORT
    zeroMem(addr result.pipe[0], 256)
    result.protocol = 0

    for t in ListenerType:
        result.protocolLabels &= $t & "\0"
    for e in EncodingType: 
        result.encodingLabels &= $e & "\0"
    for p in PlacementType: 
        result.placementLabels &= $p & "\0"
    
    result.heartbeatDataTransformation = DataTransformation()
    result.tasksDataTransformation = DataTransformation(placement: PLACEMENT_BODY)
    result.resultDataTransformation = DataTransformation(placement: PLACEMENT_BODY)
    
    result.reqPreviewGET = Textarea(showTimestamps = false, autoScroll = false)
    result.respPreviewGET = Textarea(showTimestamps = false, autoScroll = false)
    result.reqPreviewPOST = Textarea(showTimestamps = false, autoScroll = false)
    result.respPreviewPOST = Textarea(showTimestamps = false, autoScroll = false)


proc resetModalValues(component: ListenerModalComponent) =
    zeroMem(addr component.callbackHosts[0], 256 * 32)
    zeroMem(addr component.bindAddress[0], 256)
    component.bindPort = DEFAULT_PORT
    zeroMem(addr component.pipe[0], 256)
    component.protocol = 0

#[
    Profile serialization
]#
proc setCharArray(dst: var openArray[char], src: string) =
    zeroMem(addr dst[0], dst.len())
    let n = min(src.len(), dst.len() - 1)
    if n > 0: copyMem(addr dst[0], unsafeAddr src[0], n)

proc parseEncodingEntry(table: TomlTableRef): Encoding =
    let encType = table.getTableValue("type").getStr()
    case encType
    of "base64":
        result.encodingType = ENCODING_BASE64
        let urlSafe = table.getTableValue("url-safe")
        if urlSafe.kind == Bool: result.urlSafe = urlSafe.boolVal
    of "hex": result.encodingType = ENCODING_HEX
    of "rot":
        result.encodingType = ENCODING_ROT
        let key = table.getTableValue("key")
        if key.kind == Int: result.key = int32(key.intVal)
    of "xor":
        result.encodingType = ENCODING_XOR
        let key = table.getTableValue("key")
        if key.kind == Int: result.key = int32(key.intVal)
    else: result.encodingType = ENCODING_NONE

proc parseProfileEncodings(profile: Profile, path: string): seq[Encoding] =
    if profile.isArray(path & ".encoding"):
        for elem in profile.getArray(path & ".encoding"):
            let table = elem.getTable()
            if not table.isNil: result.add(parseEncodingEntry(table))
    else:
        let table = profile.getTable(path & ".encoding")
        if not table.isNil: result.add(parseEncodingEntry(table))

proc parseProfileKeyValues(profile: Profile, path: string): seq[KeyValue] =
    for (k, v) in profile.getTableKeys(path):
        var kv: KeyValue
        zeroMem(addr kv, sizeof(KeyValue))
        kv.key.setCharArray(k)
        if v.kind == Array:
            var lines: seq[string]
            for elem in profile.getArray(path & "." & k): lines.add(elem.getStr())
            kv.value.setCharArray(lines.join("\n"))
        else:
            kv.value.setCharArray(v.getStr())
        result.add(kv)

proc parseProfileDataTransformation(profile: Profile, path: string, defaultPlacement: PlacementType = PLACEMENT_BODY): DataTransformation =
    result = DataTransformation(placement: defaultPlacement)
    let placementTable = profile.getTable(path & ".placement")
    if not placementTable.isNil:
        case placementTable.getTableValue("type").getStr()
        of "header": result.placement = PLACEMENT_HEADER
        of "query": result.placement = PLACEMENT_QUERY
        else: result.placement = PLACEMENT_BODY
        result.placementName.setCharArray(placementTable.getTableValue("name").getStr())
    result.encodings = parseProfileEncodings(profile, path)
    result.prepend.setCharArray(profile.getStringOrByteArray(path & ".prepend"))
    result.append.setCharArray(profile.getStringOrByteArray(path & ".append"))

proc loadFromProfile*(component: ListenerModalComponent, profile: Profile) =
    if profile.isNil: return

    component.userAgentGET.setCharArray(profile.getString("http-get.user-agent"))
    var getEndpoints: seq[string]
    for ep in profile.getArray("http-get.endpoints"): getEndpoints.add(ep.getStr())
    component.endpointsGET.setCharArray(getEndpoints.join("\n"))
    component.reqHeadersGET = parseProfileKeyValues(profile, "http-get.agent.headers")
    component.queryParamsGET = parseProfileKeyValues(profile, "http-get.agent.parameters")
    component.heartbeatDataTransformation = parseProfileDataTransformation(profile, "http-get.agent.heartbeat")

    component.respHeadersGET = parseProfileKeyValues(profile, "http-get.server.headers")
    component.tasksDataTransformation = parseProfileDataTransformation(profile, "http-get.server.output")

    component.userAgentPOST.setCharArray(profile.getString("http-post.user-agent"))
    var postEndpoints: seq[string]
    for ep in profile.getArray("http-post.endpoints"): postEndpoints.add(ep.getStr())
    component.endpointsPOST.setCharArray(postEndpoints.join("\n"))
    
    var methods: seq[string]
    if profile.isArray("http-post.request-methods"): 
        for m in profile.getArray("http-post.request-methods"): 
            methods.add(m.getStr())
    else: 
        methods.add(profile.getString("http-post.request-methods"))
    component.methods.setCharArray(methods.join("\n"))
    component.reqHeadersPOST = parseProfileKeyValues(profile, "http-post.agent.headers")
    component.queryParamsPOST = parseProfileKeyValues(profile, "http-post.agent.parameters")
    component.resultDataTransformation = parseProfileDataTransformation(profile, "http-post.agent.output")

    component.respHeadersPOST = parseProfileKeyValues(profile, "http-post.server.headers")
    component.respBody.setCharArray(profile.getString("http-post.server.output.body"))

proc escapeToml(s: string): string = s.replace("\\", "\\\\").replace("\"", "\\\"")
proc quotedToml(s: string): string = "\"" & s.escapeToml() & "\""

proc arrayToToml(values: seq[string]): string =
    var parts: seq[string]
    for v in values: parts.add(v.quotedToml())
    return "[" & parts.join(", ") & "]"

proc encodingToToml(enc: Encoding): string =
    case enc.encodingType
    of ENCODING_NONE: return "{ type = \"none\" }"
    of ENCODING_BASE64:
        if enc.urlSafe: return "{ type = \"base64\", url-safe = true }"
        return "{ type = \"base64\" }"
    of ENCODING_HEX: return "{ type = \"hex\" }"
    of ENCODING_ROT: return "{ type = \"rot\", key = " & $enc.key & " }"
    of ENCODING_XOR: return "{ type = \"xor\", key = " & $enc.key & " }"

proc dataTransformToToml(dt: DataTransformation): string =
    let name = dt.placementName.toString()
    case dt.placement
    of PLACEMENT_BODY: result &= "placement = { type = \"body\" }\n"
    of PLACEMENT_HEADER: result &= "placement = { type = \"header\", name = " & name.quotedToml() & " }\n"
    of PLACEMENT_QUERY: result &= "placement = { type = \"query\", name = " & name.quotedToml() & " }\n"
    if dt.encodings.len() == 1:
        result &= "encoding = " & encodingToToml(dt.encodings[0]) & "\n"
    elif dt.encodings.len() > 1:
        result &= "encoding = [\n"
        for i, enc in dt.encodings:
            result &= "    " & encodingToToml(enc)
            if i < dt.encodings.len() - 1: result &= ","
            result &= "\n"
        result &= "]\n"
    let prepend = dt.prepend.toString()
    let append = dt.append.toString()
    if prepend.len() > 0: result &= "prepend = " & prepend.quotedToml() & "\n"
    if append.len() > 0: result &= "append = " & append.quotedToml() & "\n"

proc kvValueToToml(s: string): string =
    var nonEmpty: seq[string]
    for l in s.splitLines():
        let t = l.strip()
        if t.len() > 0: nonEmpty.add(t)
    if nonEmpty.len() <= 1: return s.quotedToml()
    return arrayToToml(nonEmpty)

proc keyValuesToToml(pairs: seq[KeyValue]): string =
    for pair in pairs:
        let k = pair.key.toString()
        if k.len() == 0: continue
        result &= k & " = " & pair.value.toString().kvValueToToml() & "\n"

proc toProfileToml*(component: ListenerModalComponent): string =
    proc toMultilineString(buf: openArray[char]): seq[string] =
        for line in buf.toString().splitLines():
            let trimmed = line.strip()
            if trimmed.len() > 0: result.add(trimmed)

    let 
        getUserAgent = component.userAgentGET.toString()
        getEndpoints = component.endpointsGET.toMultilineString()
        postUserAgent = component.userAgentPOST.toString()
        postEndpoints = component.endpointsPOST.toMultilineString()
        postMethods = component.methods.toMultilineString()

    result &= "[http-get]\n"
    if getUserAgent.len() > 0: result &= "user-agent = " & getUserAgent.quotedToml() & "\n"
    if getEndpoints.len() > 0: result &= "endpoints = " & arrayToToml(getEndpoints) & "\n"

    result &= "\n[http-get.agent.heartbeat]\n"
    result &= dataTransformToToml(component.heartbeatDataTransformation)

    if component.queryParamsGET.len() > 0:
        result &= "\n[http-get.agent.parameters]\n"
        result &= keyValuesToToml(component.queryParamsGET)

    if component.reqHeadersGET.len() > 0:
        result &= "\n[http-get.agent.headers]\n"
        result &= keyValuesToToml(component.reqHeadersGET)

    if component.respHeadersGET.len() > 0:
        result &= "\n[http-get.server.headers]\n"
        result &= keyValuesToToml(component.respHeadersGET)

    result &= "\n[http-get.server.output]\n"
    result &= dataTransformToToml(component.tasksDataTransformation)

    result &= "\n[http-post]\n"
    if postUserAgent.len() > 0: result &= "user-agent = " & postUserAgent.quotedToml() & "\n"
    if postEndpoints.len() > 0: result &= "endpoints = " & arrayToToml(postEndpoints) & "\n"
    if postMethods.len() > 0: result &= "request-methods = " & arrayToToml(postMethods) & "\n"

    if component.reqHeadersPOST.len() > 0:
        result &= "\n[http-post.agent.headers]\n"
        result &= keyValuesToToml(component.reqHeadersPOST)

    if component.queryParamsPOST.len() > 0:
        result &= "\n[http-post.agent.parameters]\n"
        result &= keyValuesToToml(component.queryParamsPOST)

    result &= "\n[http-post.agent.output]\n"
    result &= dataTransformToToml(component.resultDataTransformation)

    if component.respHeadersPOST.len() > 0:
        result &= "\n[http-post.server.headers]\n"
        result &= keyValuesToToml(component.respHeadersPOST)

    let respBody = component.respBody.toString()
    if respBody.len() > 0:
        result &= "\n[http-post.server.output]\n"
        result &= "body = " & respBody.quotedToml() & "\n"

#[
    Profile setting inputs
]#
proc drawKeyValueSetting(component: ListenerModalComponent, id: string, pairs: var seq[KeyValue]) =
    let 
        textSpacing = igGetStyle().ItemSpacing.x
        totalWidth = igGetContentRegionAvail().x
        keyWidth = totalWidth * 0.3
        removeWidth = igCalcTextSize("Remove", nil, false, 0.0f).x + igGetStyle().FramePadding.x * 2

    var toRemove = -1
    for i in 0 ..< pairs.len():
        igPushID_Int(int32(i))

        igSetNextItemWidth(keyWidth)
        igInputText(("##Key" & id).cstring, cast[cstring](addr pairs[i].key[0]), 256, ImGui_InputTextFlags_None.int32, nil, nil)

        igSameLine(0.0f, 0.0f)
        igText(":")
        igSameLine(0.0f, 0.0f)

        let valueWidth = igGetContentRegionAvail().x - removeWidth - textSpacing
        igSetNextItemWidth(valueWidth)
        igPushStyleVar_Float(ImGui_StyleVar_ScrollbarSize.int32, 0.0f)
        igInputTextMultiline(("##Value" & id).cstring, cast[cstring](addr pairs[i].value[0]), 4096, vec2(0.0f, pairs[i].value.contentHeight()), ImGui_InputTextFlags_None.int32, nil, nil)
        igPopStyleVar(1)

        igSameLine(0.0f, textSpacing)

        igPushStyleColor(ImGuiCol_Button.int32, CONSOLE_ERROR_DIM)
        igPushStyleColor(ImGuiCol_ButtonHovered.int32, CONSOLE_ERROR_HOVERED)
        igPushStyleColor(ImGuiCol_ButtonActive.int32, CONSOLE_ERROR)
        if igButton(("Remove##" & id).cstring, vec2(-1.0f, 0)):
            toRemove = i
        igPopStyleColor(3)

        igPopID()

    if toRemove >= 0:
        pairs.delete(toRemove)

    if igButton(("Add##" & id).cstring, vec2(-1.0f, 0)):
        var pair: KeyValue
        zeroMem(addr pair, sizeof(KeyValue))
        pairs.add(pair)

proc drawEncoding(component: ListenerModalComponent, id: string, encodings: var seq[Encoding]) =
    let 
        textSpacing = igGetStyle().ItemSpacing.x
        encodingX = igGetCursorPosX()
        encodingAvailWidth = igGetContentRegionAvail().x
        buttonSize = igGetFrameHeight()
        removeWidth = igCalcTextSize("Remove", nil, false, 0.0f).x + igGetStyle().FramePadding.x * 2
        rightSectionWidth = buttonSize * 2 + removeWidth + textSpacing * 2
    
    var toRemove = -1
    var toSwap = -1
    for i in 0 ..< encodings.len():
        if i > 0: 
            igSetCursorPosX(encodingX)
        igPushID_Int(int32(i))
        igSetNextItemWidth(100.0f)

        var enc = int32(ord(encodings[i].encodingType))
        igCombo_Str(("##EncodingType" & id).cstring, addr enc, component.encodingLabels.cstring, int32(ord(EncodingType.high) + 1))
        encodings[i].encodingType = EncodingType(enc)
        case encodings[i].encodingType
        of ENCODING_ROT, ENCODING_XOR:
            igSameLine(0.0f, textSpacing)
            igText("Key:")
            igSameLine(0.0f, textSpacing)
            igSetNextItemWidth(60.0f)
            igInputScalar(("##EncodingKey" & id).cstring, ImGuiDataType_S32.int32, addr encodings[i].key, nil, nil, "%d", ImGui_InputTextFlags_CharsDecimal.int32)
        of ENCODING_BASE64:
            igSameLine(0.0f, textSpacing)
            igCheckbox(("URL-Safe##" & id).cstring, addr encodings[i].urlSafe)
        else: 
            discard
        
        igSameLine(encodingX + encodingAvailWidth - rightSectionWidth, 0.0f)
        
        # Encoding reordering 
        if i == 0: # Disable up arrow on first encoding
            igBeginDisabled(true)
        if igButton((ICON_FA_ARROW_UP & "##MoveUp").cstring, vec2(buttonSize, 0)):
            toSwap = i - 1
        if i == 0: 
            igEndDisabled()
        
        igSameLine(0.0f, textSpacing)
        
        if i == encodings.len() - 1: # Disable down arrow on last encoding
            igBeginDisabled(true)
        if igButton((ICON_FA_ARROW_DOWN & "##MoveDown").cstring, vec2(buttonSize, 0)):
            toSwap = i
        if i == encodings.len() - 1: 
            igEndDisabled()
        igSameLine(0.0f, textSpacing)
        
        # Remove button
        igPushStyleColor(ImGuiCol_Button.int32, CONSOLE_ERROR_DIM)
        igPushStyleColor(ImGuiCol_ButtonHovered.int32, CONSOLE_ERROR_HOVERED)
        igPushStyleColor(ImGuiCol_ButtonActive.int32, CONSOLE_ERROR)
        if igButton(("Remove##EncodingRemove").cstring, vec2(-1.0f, 0)):
            toRemove = i
        igPopStyleColor(3)
        igPopID()

    if toSwap >= 0:
        swap(encodings[toSwap], encodings[toSwap + 1])
    
    if toRemove >= 0:
        encodings.delete(toRemove)
    
    if encodings.len() == 0: 
        igSameLine(0.0f, textSpacing)
    else: 
        igSetCursorPosX(encodingX)
    
    # Add button
    if igButton(("Add##EncodingAdd" & id).cstring, vec2(-1.0f, 0)):
        encodings.add(Encoding())

proc drawDataTransformation(component: ListenerModalComponent, id: string, dataTransform: DataTransformation) =
    let textSpacing = igGetStyle().ItemSpacing.x
    var availableSize = igGetContentRegionAvail()

    igText("Placement:  ")
    igSameLine(0.0f, textSpacing)
    igSetNextItemWidth(100.0f)

    var placementIdx = int32(ord(dataTransform.placement))
    if id == "http-get.server.output":
        igBeginDisabled(true)
    igCombo_Str(("##PlacementType" & id).cstring, addr placementIdx, component.placementLabels.cstring, int32(ord(PlacementType.high) + 1))
    if id == "http-get.server.output":
        igEndDisabled()
    dataTransform.placement = PlacementType(placementIdx)

    if dataTransform.placement != PLACEMENT_BODY:
        igSameLine(0.0f, textSpacing)
        igText("Name:")
        igSameLine(0.0f, textSpacing)
        availableSize = igGetContentRegionAvail()
        igSetNextItemWidth(availableSize.x)
        igInputText(("##PlacementName" & id).cstring, cast[cstring](addr dataTransform.placementName[0]), 256, ImGui_InputTextFlags_None.int32, nil, nil)

    igText("Encoding:   ")
    igSameLine(0.0f, textSpacing)
    component.drawEncoding(id, dataTransform.encodings)

    igText("Prepend:    ")
    igSameLine(0.0f, textSpacing)
    availableSize = igGetContentRegionAvail()
    igSetNextItemWidth(availableSize.x)
    igInputText(("##Prepend" & id).cstring, cast[cstring](addr dataTransform.prepend[0]), 4096, ImGui_InputTextFlags_None.int32, nil, nil)

    igText("Append:     ")
    igSameLine(0.0f, textSpacing)
    availableSize = igGetContentRegionAvail()
    igSetNextItemWidth(availableSize.x)
    igInputText(("##Append" & id).cstring, cast[cstring](addr dataTransform.append[0]), 4096, ImGui_InputTextFlags_None.int32, nil, nil)

#[
    Preview generation
]#
proc encode(data: string, encodings: seq[Encoding]): string =
    result = data
    for enc in encodings:
        case enc.encodingType
        of ENCODING_NONE: discard
        of ENCODING_BASE64: result = encode(result, safe = enc.urlSafe).replace("=", "")
        of ENCODING_HEX: result = result.toHex().toLowerAscii()
        of ENCODING_ROT:
            var s = ""
            for c in result: s &= char((int(c) + enc.key) and 0xFF)
            result = s
        of ENCODING_XOR:
            var s = ""
            for c in result: s &= char(int(c) xor enc.key)
            result = s

proc firstLine(s: string): tuple[text: string, randomized: bool] =
    let idx = s.find('\n')
    if idx < 0: return (s, false)
    return (s[0 ..< idx], true)

proc kvToQueryString(pairs: seq[KeyValue]): string =
    var parts: seq[string]
    for pair in pairs:
        let key = pair.key.toString()
        let (value, _) = pair.value.toString().firstLine()
        if key.len() > 0: parts.add(key & "=" & value)
    if parts.len() > 0: result = "?" & parts.join("&")

proc firstEndpoint(buf: openArray[char]): string =
    for line in buf.toString().splitLines():
        let ep = line.strip()
        if ep.len() > 0: return ep
    return "/"

type PreviewLine = seq[tuple[text: string, color: ImVec4]]

proc addLine(lines: var seq[PreviewLine], segments: varargs[tuple[text: string, color: ImVec4]]) =
    var line: PreviewLine
    for seg in segments:
        if seg.text.len() > 0: line.add(seg)
    if line.len() > 0: lines.add(line)

proc addHeaderLines(lines: var seq[PreviewLine], pairs: seq[KeyValue]) =
    for pair in pairs:
        let k = pair.key.toString()
        let (v, _) = pair.value.toString().firstLine()
        if k.len() > 0: lines.addLine((k & ": " & v, CONSOLE_DEFAULT))

proc previewFingerprint(lines: seq[PreviewLine]): string =
    for line in lines:
        for seg in line: result &= seg.text
        result &= "\n"

proc colorizeSegments(line: PreviewLine): PreviewLine =
    for seg in line:
        var current = ""
        for c in seg.text:
            if c in {'#', '$'}:
                if current.len() > 0: result.add((current, seg.color))
                result.add(($c, CONSOLE_WARNING))
                current = ""
            else:
                current &= c
        if current.len() > 0: result.add((current, seg.color))

proc updatePreview(textarea: TextareaWidget, cache: var string, lines: seq[PreviewLine]) =
    let fp = previewFingerprint(lines)
    if fp == cache: return
    cache = fp
    textarea.clear()
    for line in lines:
        discard textarea.addItem(LOG_OUTPUT, colorizeSegments(line))

proc generateGetRequest(component: ListenerModalComponent) =
    var lines: seq[PreviewLine]
    let endpoint = firstEndpoint(component.endpointsGET)
    let query = kvToQueryString(component.queryParamsGET)
    let encoded = encode(PLACEHOLDER, component.heartbeatDataTransformation.encodings)
    let prepend = component.heartbeatDataTransformation.prepend.toString()
    let append = component.heartbeatDataTransformation.append.toString()
    let placementName = component.heartbeatDataTransformation.placementName.toString()
    let ua = component.userAgentGET.toString()

    case component.heartbeatDataTransformation.placement
    of PLACEMENT_HEADER:
        lines.addLine(("GET " & endpoint & query & " HTTP/1.1", CONSOLE_DEFAULT))
        if ua.len() > 0: lines.addLine(("User-Agent: " & ua, CONSOLE_DEFAULT))
        lines.addHeaderLines(component.reqHeadersGET)
        lines.addLine((placementName & ": " & prepend, CONSOLE_DEFAULT), (encoded, CONSOLE_INFO), (append, CONSOLE_DEFAULT))
    of PLACEMENT_QUERY:
        let payload = prepend & encoded & append
        lines.addLine(("GET " & endpoint & query & (if query.len() > 0: "&" else: "?") & placementName & "=" & payload & " HTTP/1.1", CONSOLE_DEFAULT))
        if ua.len() > 0: lines.addLine(("User-Agent: " & ua, CONSOLE_DEFAULT))
        lines.addHeaderLines(component.reqHeadersGET)
    of PLACEMENT_BODY:
        lines.addLine(("GET " & endpoint & query & " HTTP/1.1", CONSOLE_DEFAULT))
        if ua.len() > 0: lines.addLine(("User-Agent: " & ua, CONSOLE_DEFAULT))
        lines.addHeaderLines(component.reqHeadersGET)
        lines.addLine((prepend, CONSOLE_DEFAULT), (encoded, CONSOLE_INFO), (append, CONSOLE_DEFAULT))
    component.reqPreviewGET.updatePreview(component.previewCacheGETReq, lines)

proc generateGetResponse(component: ListenerModalComponent) =
    var lines: seq[PreviewLine]
    let encoded = encode(PLACEHOLDER, component.tasksDataTransformation.encodings)
    let prepend = component.tasksDataTransformation.prepend.toString()
    let append = component.tasksDataTransformation.append.toString()

    lines.addLine(("HTTP/1.1 200 OK", CONSOLE_DEFAULT))
    lines.addHeaderLines(component.respHeadersGET)
    lines.addLine((prepend, CONSOLE_DEFAULT), (encoded, CONSOLE_INFO), (append, CONSOLE_DEFAULT))
    component.respPreviewGET.updatePreview(component.previewCacheGETResp, lines)

proc generatePostRequest(component: ListenerModalComponent) =
    var lines: seq[PreviewLine]
    let endpoint = firstEndpoint(component.endpointsPOST)
    let query = kvToQueryString(component.queryParamsPOST)
    let methodStr = component.methods.toString()
    let (verb, _) = (if methodStr.len() > 0: methodStr.firstLine() else: ("POST", false))
    let encoded = encode(PLACEHOLDER, component.resultDataTransformation.encodings)
    let prepend = component.resultDataTransformation.prepend.toString()
    let append = component.resultDataTransformation.append.toString()
    let placementName = component.resultDataTransformation.placementName.toString()
    let ua = component.userAgentPOST.toString()

    case component.resultDataTransformation.placement
    of PLACEMENT_HEADER:
        lines.addLine((verb & " " & endpoint & query & " HTTP/1.1", CONSOLE_DEFAULT))
        if ua.len() > 0: lines.addLine(("User-Agent: " & ua, CONSOLE_DEFAULT))
        lines.addHeaderLines(component.reqHeadersPOST)
        lines.addLine((placementName & ": " & prepend, CONSOLE_DEFAULT), (encoded, CONSOLE_INFO), (append, CONSOLE_DEFAULT))
    of PLACEMENT_BODY:
        lines.addLine((verb & " " & endpoint & query & " HTTP/1.1", CONSOLE_DEFAULT))
        if ua.len() > 0: lines.addLine(("User-Agent: " & ua, CONSOLE_DEFAULT))
        lines.addHeaderLines(component.reqHeadersPOST)
        lines.addLine((prepend, CONSOLE_DEFAULT), (encoded, CONSOLE_INFO), (append, CONSOLE_DEFAULT))
    of PLACEMENT_QUERY:
        let payload = prepend & encoded & append
        lines.addLine((verb & " " & endpoint & query & (if query.len() > 0: "&" else: "?") & placementName & "=" & payload & " HTTP/1.1", CONSOLE_DEFAULT))
        if ua.len() > 0: lines.addLine(("User-Agent: " & ua, CONSOLE_DEFAULT))
        lines.addHeaderLines(component.reqHeadersPOST)
    component.reqPreviewPOST.updatePreview(component.previewCachePOSTReq, lines)

proc generatePostResponse(component: ListenerModalComponent) =
    var lines: seq[PreviewLine]
    lines.addLine(("HTTP/1.1 200 OK", CONSOLE_DEFAULT))
    lines.addHeaderLines(component.respHeadersPOST)
    let body = component.respBody.toString()
    if body.len() > 0: lines.addLine((body, CONSOLE_DEFAULT))
    component.respPreviewPOST.updatePreview(component.previewCachePOSTResp, lines)

#[
    Draw
]#
proc draw*(component: ListenerModalComponent): UIListener =
    let textSpacing = igGetStyle().ItemSpacing.x

    # Center modal
    let vp = igGetMainViewport()
    var center = ImGuiViewport_GetCenter(vp)
    igSetNextWindowPos(center, ImGuiCond_Appearing.int32, vec2(0.5f, 0.5f))

    let modalWidth = max(600.0f, vp.Size.x * 0.25)
    let modalHeight = if component.profileSettingsOpen and cast[ListenerType](component.protocol) != LISTENER_SMB: max(700.0f, vp.Size.y * 0.5) else: 0.0f

    igSetNextWindowSize(vec2(modalWidth, modalHeight), ImGuiCond_Always.int32)
    let previewHeight = 8.0f * igGetTextLineHeightWithSpacing()

    var show = true
    if igBeginPopupModal("Start Listener", addr show, ImGuiWindowFlags_NoResize.int32 or ImGui_WindowFlags_NoScrollbar.int32):
        defer: igEndPopup()

        var disableStart = false

        # Listener protocol/type dropdown selection
        igText("Listener Type:    ")
        igSameLine(0.0f, textSpacing)
        var availableSize = igGetContentRegionAvail()
        igSetNextItemWidth(availableSize.x)
        igCombo_Str("##InputProtocol", addr component.protocol, component.protocolLabels.cstring, int32(ord(ListenerType.high) + 1))

        igDummy(vec2(0.0f, 10.0f))
        igSeparator()
        igDummy(vec2(0.0f, 10.0f))

        case cast[ListenerType](component.protocol):
        of LISTENER_HTTP:
            # Listener bindAddress
            igText("Host (Bind):      ")
            igSameLine(0.0f, textSpacing)
            availableSize = igGetContentRegionAvail()
            igSetNextItemWidth(availableSize.x)
            igInputTextWithHint("##InputAddressBind", "0.0.0.0", cast[cstring](addr component.bindAddress[0]), 256, ImGui_InputTextFlags_CharsNoBlank.int32, nil, nil)

            # Listener bindPort
            let step: uint16 = 1
            igText("Port (Bind):      ")
            igSameLine(0.0f, textSpacing)
            igSetNextItemWidth(availableSize.x)
            igInputScalar("##InputPortBind", ImGuiDataType_U16.int32, addr component.bindPort, addr step, nil, "%hu", ImGui_InputTextFlags_CharsDecimal.int32)

            # Callback hosts
            igText("Hosts (Callback): ")
            igSameLine(0.0f, textSpacing)
            availableSize = igGetContentRegionAvail()
            igSetNextItemWidth(availableSize.x)
            igInputTextMultiline("##InputCallbackHosts", cast[cstring](addr component.callbackHosts[0]), 256 * 32, vec2(0.0f, 3.0f * igGetTextLineHeightWithSpacing()), ImGui_InputTextFlags_CharsNoBlank.int32, nil, nil)

            # Only enabled the start button when valid values have been entered
            disableStart = (component.bindAddress.toString() == "") or (component.bindPort <= 0)

        of LISTENER_SMB:
            # SMB Pipe name
            igText("Pipe name:        ")
            igSameLine(0.0f, textSpacing)
            igText("\\\\.\\pipe\\")
            igSameLine(0.0f, textSpacing)
            availableSize = igGetContentRegionAvail()
            igSetNextItemWidth(availableSize.x)
            igInputText("##InputPipe", cast[cstring](addr component.pipe[0]), 256, ImGui_InputTextFlags_CharsNoBlank.int32, nil, nil)

            # Only enabled the start button when valid values have been entered
            disableStart = component.pipe.toString() == ""

        # Network profile overwrites (HTTP Listeners only)
        if cast[ListenerType](component.protocol) == LISTENER_HTTP:

            igDummy(vec2(0.0f, 10.0f))

            component.profileSettingsOpen = igTreeNodeEx_Str("Network Profile Settings", ImGuiTreeNodeFlags_NoTreePushOnOpen.int32) 
            if component.profileSettingsOpen: 

                igDummy(vec2(0.0f, 10.0f))

                # Import/Export buttons
                availableSize = igGetContentRegionAvail()            
                if igButton("Import", vec2(availableSize.x * 0.5 - textSpacing * 0.5, 0.0f)):
                    let path = callDialogFileOpen("Load Profile", "", [("*.toml", "*.toml")])
                    if path.len() != 0: 
                        component.loadFromProfile(parseString(readFile(path)))

                igSameLine(0.0f, textSpacing)

                if igButton("Export", vec2(availableSize.x * 0.5 - textSpacing * 0.5, 0.0f)):
                    let defaultName = "listener_" & $cast[ListenerType](component.protocol) & ".toml"
                    let path = callDialogFileSave("Save Profile", defaultName)
                    if path.len() != 0: 
                        writeFile(path, component.toProfileToml())

                igDummy(vec2(0.0f, 10.0f))

                # Profile settings
                if igBeginTabBar("##Tabs", ImGuiTabBarFlags_None.int32):
                    defer: igEndTabBar()

                    availableSize = igGetContentRegionAvail()
                    let contentHeight = availableSize.y - igGetFrameHeightWithSpacing() - 10.0f

                    # Tab 1: Agent GET Request: Heartbeat
                    if igBeginTabItem(fmt"GET {ICON_FA_ARROW_RIGHT} Heartbeat".cstring, nil, ImGuiTabBarFlags_None.int32):
                        defer: igEndTabItem()
                        discard igBeginChild_Str("##Tab1Scroll", vec2(0, contentHeight), ImGuiChildFlags_None.int32, ImGuiWindowFlags_None.int32)
                        defer: igEndChild()
                        igDummy(vec2(0.0f, 8.0f))

                        igText("User-Agent: ")
                        igSameLine(0.0f, textSpacing)
                        availableSize = igGetContentRegionAvail()
                        igSetNextItemWidth(availableSize.x)
                        igInputText("##http-get.user-agent", cast[cstring](addr component.userAgentGET[0]), 256, ImGui_InputTextFlags_None.int32, nil, nil)

                        igText("Endpoints:  ")
                        igSameLine(0.0f, textSpacing)
                        availableSize = igGetContentRegionAvail()
                        igSetNextItemWidth(availableSize.x)
                        igPushStyleVar_Float(ImGui_StyleVar_ScrollbarSize.int32, 0.0f)
                        igInputTextMultiline("##http-get.endpoints", cast[cstring](addr component.endpointsGET[0]), 256 * 32, vec2(0.0f, component.endpointsGET.contentHeight()), ImGui_InputTextFlags_None.int32, nil, nil)
                        igPopStyleVar(1)

                        igSeparatorText("Request Headers")
                        component.drawKeyValueSetting("http-get.agent.headers", component.reqHeadersGET)

                        igSeparatorText("Query Parameters")
                        component.drawKeyValueSetting("http-get.agent.parameters", component.queryParamsGET)

                        igSeparatorText("Data Transformation: Heartbeat")
                        component.drawDataTransformation("http-get.agent.heartbeat", component.heartbeatDataTransformation)

                        igSeparatorText("Preview")
                        generateGetRequest(component)
                        availableSize = igGetContentRegionAvail()
                        component.reqPreviewGET.draw(vec2(availableSize.x, previewHeight))

                    # Tab 2: Server GET Response: Tasks
                    if igBeginTabItem(fmt"GET {ICON_FA_ARROW_LEFT} Tasks".cstring, nil, ImGuiTabBarFlags_None.int32):
                        defer: igEndTabItem()
                        discard igBeginChild_Str("##Tab2Scroll", vec2(0, contentHeight), ImGuiChildFlags_None.int32, ImGuiWindowFlags_None.int32)
                        defer: igEndChild()
                        igDummy(vec2(0.0f, 8.0f))

                        igSeparatorText("Response Headers")
                        component.drawKeyValueSetting("http-get.server.headers", component.respHeadersGET)

                        igSeparatorText("Data Transformation: Tasks")
                        component.drawDataTransformation("http-get.server.output", component.tasksDataTransformation)

                        igSeparatorText("Preview")
                        generateGetResponse(component)
                        availableSize = igGetContentRegionAvail()
                        component.respPreviewGET.draw(vec2(availableSize.x, previewHeight))

                    # Tab 3: Agent POST Request: Task Results/Registration
                    if igBeginTabItem(fmt"POST {ICON_FA_ARROW_RIGHT} Results".cstring, nil, ImGuiTabBarFlags_None.int32):
                        defer: igEndTabItem()
                        discard igBeginChild_Str("##Tab3Scroll", vec2(0, contentHeight), ImGuiChildFlags_None.int32, ImGuiWindowFlags_None.int32)
                        defer: igEndChild()
                        igDummy(vec2(0.0f, 8.0f))

                        igText("User-Agent:      ")
                        igSameLine(0.0f, textSpacing)
                        availableSize = igGetContentRegionAvail()
                        igSetNextItemWidth(availableSize.x)
                        igInputText("##http-post.user-agent", cast[cstring](addr component.userAgentPOST[0]), 256, ImGui_InputTextFlags_None.int32, nil, nil)

                        igText("Endpoints:       ")
                        igSameLine(0.0f, textSpacing)
                        availableSize = igGetContentRegionAvail()
                        igSetNextItemWidth(availableSize.x)
                        igPushStyleVar_Float(ImGui_StyleVar_ScrollbarSize.int32, 0.0f)
                        igInputTextMultiline("##http-post.endpoints", cast[cstring](addr component.endpointsPOST[0]), 256 * 32, vec2(0.0f, component.endpointsPOST.contentHeight()), ImGui_InputTextFlags_None.int32, nil, nil)
                        igPopStyleVar(1)

                        igText("Request Methods: ")
                        igSameLine(0.0f, textSpacing)
                        availableSize = igGetContentRegionAvail()
                        igSetNextItemWidth(availableSize.x)
                        igPushStyleVar_Float(ImGui_StyleVar_ScrollbarSize.int32, 0.0f)
                        igInputTextMultiline("##http-post.request-methods", cast[cstring](addr component.methods[0]), 256 * 32, vec2(0.0f, component.methods.contentHeight()), ImGui_InputTextFlags_None.int32, nil, nil)
                        igPopStyleVar(1)

                        igSeparatorText("Request Headers")
                        component.drawKeyValueSetting("http-post.agent.headers", component.reqHeadersPOST)

                        igSeparatorText("Query Parameters")
                        component.drawKeyValueSetting("http-post.agent.parameters", component.queryParamsPOST)

                        igSeparatorText("Data Transformation: Task Results & Registration")
                        component.drawDataTransformation("http-post.agent.output", component.resultDataTransformation)

                        igSeparatorText("Preview")
                        generatePostRequest(component)
                        availableSize = igGetContentRegionAvail()
                        component.reqPreviewPOST.draw(vec2(availableSize.x, previewHeight))

                    # Tab 4: Server POST Response
                    if igBeginTabItem(fmt"POST {ICON_FA_ARROW_LEFT} Response".cstring, nil, ImGuiTabBarFlags_None.int32):
                        defer: igEndTabItem()
                        discard igBeginChild_Str("##Tab4Scroll", vec2(0, contentHeight), ImGuiChildFlags_None.int32, ImGuiWindowFlags_None.int32)
                        defer: igEndChild()
                        igDummy(vec2(0.0f, 8.0f))

                        igSeparatorText("Response Headers")
                        component.drawKeyValueSetting("http-post.server.headers", component.respHeadersPOST)

                        igSeparatorText("Response Body")
                        availableSize = igGetContentRegionAvail()
                        igInputTextMultiline("##http-post.server.output", cast[cstring](addr component.respBody[0]), MAX_INPUT_LENGTH, vec2(availableSize.x, 3.0f * igGetTextLineHeightWithSpacing()), ImGui_InputTextFlags_None.int32, nil, nil)

                        igSeparatorText("Preview")
                        generatePostResponse(component)
                        availableSize = igGetContentRegionAvail()
                        component.respPreviewPOST.draw(vec2(availableSize.x, previewHeight))

        igDummy(vec2(0.0f, 10.0f))

        # Buttons
        availableSize = igGetContentRegionAvail()
        igBeginDisabled(disableStart)
        if igButton("Start", vec2(availableSize.x * 0.5 - textSpacing * 0.5, 0.0f)):

            let uuid = generateUUID()

            # Process input values
            case cast[ListenerType](component.protocol):
            of LISTENER_HTTP:
                var hosts: string = ""
                let
                    callbackHosts = $cast[cstring]((addr component.callbackHosts[0]))
                    bindAddress = $cast[cstring]((addr component.bindAddress[0]))
                    bindPort =  int(component.bindPort)

                if callbackHosts.isEmptyOrWhitespace():
                    hosts &= bindAddress & ":"  & $bindPort

                else:
                    for host in callbackHosts.splitLines():
                        if host.isEmptyOrWhitespace():
                            continue

                        hosts &= ";"
                        let hostParts = host.split(":")
                        if hostParts.len() == 2:
                            if not hostParts[1].isEmptyOrWhitespace():
                                hosts &= hostParts[0] & ":" & hostParts[1]
                            else:
                                hosts &= hostParts[0] & ":" & $bindPort
                        elif hostParts.len() == 1 and not hostParts[0].isEmptyOrWhitespace():
                            hosts &= hostParts[0] & ":" & $bindPort

                    hosts.removePrefix(";")

                # Return new listener object
                result = UIListener(
                    listenerId: uuid,
                    listenerType: LISTENER_HTTP,
                    hosts: hosts,
                    address: bindAddress,
                    port: bindPort
                )

            of LISTENER_SMB:
                let pipe = $cast[cstring]((addr component.pipe[0]))
                result = UIListener(
                    listenerId: uuid,
                    listenerType: LISTENER_SMB,
                    pipe: "\\\\.\\pipe\\" & pipe
                )

            component.resetModalValues()
            igCloseCurrentPopup()

        igEndDisabled()
        igSameLine(0.0f, textSpacing)

        if igButton("Close", vec2(availableSize.x * 0.5 - textSpacing * 0.5, 0.0f)):
            component.resetModalValues()
            igCloseCurrentPopup()

        igSameLine(0.0f, textSpacing)