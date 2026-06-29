import strutils, strformat, base64, random, sequtils, hashes
import imguin/[cimgui, glfw_opengl]
import ../widgets/textarea
import ../../utils/[appImGui, utils, globals, dialogs]
import ../../../common/[utils, profile]
import ../../../common/toml/toml
import ../../../types/[common, client]

const
    DEFAULT_PORT = 8080'u16
    PLACEHOLDER = "[PLACEHOLDER]"

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
    component.editingListener = nil
    zeroMem(addr component.name[0], 256)
    component.protocol = 0
    zeroMem(addr component.callbackHosts[0], 256 * 32)
    zeroMem(addr component.bindAddress[0], 256)
    component.bindPort = DEFAULT_PORT
    zeroMem(addr component.pipe[0], 256)
    component.profileSettingsOpen = false

#[
    Profile serialization
]#
proc setValue(dst: var openArray[char], src: string) =
    zeroMem(addr dst[0], dst.len())
    let n = min(src.len(), dst.len() - 1)
    if n > 0: copyMem(addr dst[0], unsafeAddr src[0], n)

proc parseEncoding(table: TomlTableRef): Encoding =
    let encType = table.getTableValue("type").getStr()
    case encType
    of "base64":
        result.encodingType = ENCODING_BASE64
        let urlSafe = table.getTableValue("url-safe")
        if urlSafe.kind == Bool: 
            result.urlSafe = urlSafe.boolVal
    of "hex": 
        result.encodingType = ENCODING_HEX
    of "rot":
        result.encodingType = ENCODING_ROT
        let key = table.getTableValue("key")
        if key.kind == Int: 
            result.key = int32(key.intVal)
    of "xor":
        result.encodingType = ENCODING_XOR
        let key = table.getTableValue("key")
        if key.kind == Int: 
            result.key = int32(key.intVal)
    else: 
        result.encodingType = ENCODING_NONE

proc parseEncodings(profile: Profile, path: string): seq[Encoding] =
    if profile.isArray(path):
        for elem in profile.getArray(path):
            let table = elem.getTable()
            if not table.isNil: 
                result.add(parseEncoding(table))
    else:
        let table = profile.getTable(path)
        if not table.isNil: 
            result.add(parseEncoding(table))

proc parseSetting(profile: Profile, path: string): seq[KeyValue] =
    for (k, v) in profile.getTableKeys(path):
        var kv: KeyValue
        zeroMem(addr kv, sizeof(KeyValue))
        kv.key.setValue(k)
        
        if v.kind == Array:
            var lines: seq[string]
            for elem in profile.getArray(path & "." & k): 
                lines.add(elem.getStr())
            kv.value.setValue(lines.join("\n"))
        else:
            kv.value.setValue(v.getStr())
        
        result.add(kv)

proc parseDataTransformation(profile: Profile, path: string, defaultPlacement: PlacementType = PLACEMENT_BODY): DataTransformation =
    result = DataTransformation(placement: defaultPlacement)
    let placementTable = profile.getTable(path & ".placement")
    if not placementTable.isNil:
        case placementTable.getTableValue("type").getStr()
        of "header": result.placement = PLACEMENT_HEADER
        of "query": result.placement = PLACEMENT_QUERY
        else: result.placement = PLACEMENT_BODY
        result.placementName.setValue(placementTable.getTableValue("name").getStr())
    result.encodings = parseEncodings(profile, path & ".encoding")
    result.prepend.setValue(profile.getStringOrByteArray(path & ".prepend"))
    result.append.setValue(profile.getStringOrByteArray(path & ".append"))

proc setProfile*(component: ListenerModalComponent, profile: Profile) =
    if profile.isNil: 
        return

    if profile.isArray("http-get.user-agent"):
        var userAgents: seq[string]
        for userAgent in profile.getArray("http-get.user-agent"): userAgents.add(userAgent.getStr())
        component.userAgentGET.setValue(userAgents.join("\n"))
    else:
        component.userAgentGET.setValue(profile.getString("http-get.user-agent"))

    var endpointsGET: seq[string]
    for endpoint in profile.getArray("http-get.endpoints"): 
        endpointsGET.add(endpoint.getStr())
    component.endpointsGET.setValue(endpointsGET.join("\n"))
    component.reqHeadersGET = parseSetting(profile, "http-get.agent.headers")
    component.queryParamsGET = parseSetting(profile, "http-get.agent.parameters")
    component.heartbeatDataTransformation = parseDataTransformation(profile, "http-get.agent.heartbeat")

    component.respHeadersGET = parseSetting(profile, "http-get.server.headers")
    component.tasksDataTransformation = parseDataTransformation(profile, "http-get.server.output")

    if profile.isArray("http-post.user-agent"):
        var userAgents: seq[string]
        for userAgent in profile.getArray("http-post.user-agent"): userAgents.add(userAgent.getStr())
        component.userAgentPOST.setValue(userAgents.join("\n"))
    else:
        component.userAgentPOST.setValue(profile.getString("http-post.user-agent"))

    var endpointsPOST: seq[string]
    for endpoint in profile.getArray("http-post.endpoints"): 
        endpointsPOST.add(endpoint.getStr())
    component.endpointsPOST.setValue(endpointsPOST.join("\n"))
    
    var methods: seq[string]
    if profile.isArray("http-post.request-methods"): 
        for m in profile.getArray("http-post.request-methods"): 
            methods.add(m.getStr())
    else: 
        methods.add(profile.getString("http-post.request-methods"))
    component.methods.setValue(methods.join("\n"))
    
    component.reqHeadersPOST = parseSetting(profile, "http-post.agent.headers")
    component.queryParamsPOST = parseSetting(profile, "http-post.agent.parameters")
    component.resultDataTransformation = parseDataTransformation(profile, "http-post.agent.output")

    component.respHeadersPOST = parseSetting(profile, "http-post.server.headers")
    component.respBody.setValue(profile.getString("http-post.server.output.body"))

proc setEdit*(component: ListenerModalComponent, listener: UIListener) =
    component.editingListener = listener
    component.name.setValue(listener.name)
    component.protocol = int32(ord(listener.listenerType))
    case listener.listenerType:
    of LISTENER_HTTP:
        component.bindAddress.setValue(listener.address)
        component.bindPort = uint16(listener.port)
        component.callbackHosts.setValue(listener.hosts.replace(";", "\n"))
        component.setProfile(parseString(listener.profile))
    of LISTENER_SMB:
        component.pipe.setValue(listener.pipe.replace("\\\\.\\pipe\\", ""))

# Escape and quote TOML string
proc quoted(s: string): string = "\"" & s.replace("\\", "\\\\").replace("\"", "\\\"") & "\""

proc toTomlArray(values: seq[string]): string =
    var parts: seq[string]
    for v in values: parts.add(v.quoted())
    return "[" & parts.join(", ") & "]"

proc toTomlEncoding(enc: Encoding): string =
    case enc.encodingType
    of ENCODING_NONE: 
        return "{ type = \"none\" }"
    of ENCODING_BASE64:
        if enc.urlSafe: 
            return "{ type = \"base64\", url-safe = true }"
        return "{ type = \"base64\" }"
    of ENCODING_HEX: 
        return "{ type = \"hex\" }"
    of ENCODING_ROT: 
        return "{ type = \"rot\", key = " & $enc.key & " }"
    of ENCODING_XOR: 
        return "{ type = \"xor\", key = " & $enc.key & " }"

proc dataTransformToToml(dataTransform: DataTransformation): string =
    let name = dataTransform.placementName.toString()
    case dataTransform.placement
    of PLACEMENT_BODY: 
        result &= "placement = { type = \"body\" }\n"
    of PLACEMENT_HEADER: 
        result &= "placement = { type = \"header\", name = " & name.quoted() & " }\n"
    of PLACEMENT_QUERY: 
        result &= "placement = { type = \"query\", name = " & name.quoted() & " }\n"
    
    if dataTransform.encodings.len() == 1:
        result &= "encoding = " & toTomlEncoding(dataTransform.encodings[0]) & "\n"
    elif dataTransform.encodings.len() > 1:
        result &= "encoding = [\n"
        for i, enc in dataTransform.encodings:
            result &= "    " & toTomlEncoding(enc)
            if i < dataTransform.encodings.len() - 1: result &= ","
            result &= "\n"
        result &= "]\n"
        
    result &= "prepend = " & dataTransform.prepend.toString().quoted() & "\n"
    result &= "append = " & dataTransform.append.toString().quoted() & "\n"

proc toTomlKeyValue(s: string): string =
    var nonEmpty: seq[string]
    for l in s.splitLines():
        let t = l.strip()
        if t.len() > 0: 
            nonEmpty.add(t)
    if nonEmpty.len() <= 1: 
        return s.quoted()
    return toTomlArray(nonEmpty)

proc toTomlSetting(pairs: seq[KeyValue]): string =
    for pair in pairs:
        let k = pair.key.toString()
        if k.len() != 0: 
            result &= k & " = " & pair.value.toString().toTomlKeyValue() & "\n"

proc toTomlProfile*(component: ListenerModalComponent): string =
    
    proc toMultilineString(buf: openArray[char]): seq[string] =
        for line in buf.toString().splitLines():
            let trimmed = line.strip()
            if trimmed.len() > 0: result.add(trimmed)
    
    result &= "name = " & component.name.toString().quoted() & "\n"

    let
        getUserAgents = component.userAgentGET.toMultilineString()
        endpointsGET = component.endpointsGET.toMultilineString()
        postUserAgents = component.userAgentPOST.toMultilineString()
        endpointsPOST = component.endpointsPOST.toMultilineString()
        postMethods = component.methods.toMultilineString()

    result &= "\n[http-get]\n"
    if getUserAgents.len() == 1: result &= "user-agent = " & getUserAgents[0].quoted() & "\n"
    elif getUserAgents.len() > 1: result &= "user-agent = " & toTomlArray(getUserAgents) & "\n"
    if endpointsGET.len() > 0: result &= "endpoints = " & toTomlArray(endpointsGET) & "\n"

    result &= "\n[http-get.agent.heartbeat]\n"
    result &= dataTransformToToml(component.heartbeatDataTransformation)

    if component.queryParamsGET.len() > 0:
        result &= "\n[http-get.agent.parameters]\n"
        result &= toTomlSetting(component.queryParamsGET)

    if component.reqHeadersGET.len() > 0:
        result &= "\n[http-get.agent.headers]\n"
        result &= toTomlSetting(component.reqHeadersGET)

    if component.respHeadersGET.len() > 0:
        result &= "\n[http-get.server.headers]\n"
        result &= toTomlSetting(component.respHeadersGET)

    result &= "\n[http-get.server.output]\n"
    result &= dataTransformToToml(component.tasksDataTransformation)

    result &= "\n[http-post]\n"
    if postUserAgents.len() == 1: result &= "user-agent = " & postUserAgents[0].quoted() & "\n"
    elif postUserAgents.len() > 1: result &= "user-agent = " & toTomlArray(postUserAgents) & "\n"
    if endpointsPOST.len() > 0: result &= "endpoints = " & toTomlArray(endpointsPOST) & "\n"
    if postMethods.len() > 0: result &= "request-methods = " & toTomlArray(postMethods) & "\n"

    if component.reqHeadersPOST.len() > 0:
        result &= "\n[http-post.agent.headers]\n"
        result &= toTomlSetting(component.reqHeadersPOST)

    if component.queryParamsPOST.len() > 0:
        result &= "\n[http-post.agent.parameters]\n"
        result &= toTomlSetting(component.queryParamsPOST)

    result &= "\n[http-post.agent.output]\n"
    result &= dataTransformToToml(component.resultDataTransformation)

    if component.respHeadersPOST.len() > 0:
        result &= "\n[http-post.server.headers]\n"
        result &= toTomlSetting(component.respHeadersPOST)

    let respBody = component.respBody.toString()
    if respBody.len() > 0:
        result &= "\n[http-post.server.output]\n"
        result &= "body = " & respBody.quoted() & "\n"

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
type PreviewLine = seq[tuple[text: string, color: ImVec4]]

proc encode(data: string, encodings: seq[Encoding]): string =
    result = data
    for enc in encodings:
        case enc.encodingType
        of ENCODING_NONE: 
            discard
        of ENCODING_BASE64: 
            result = encode(result, safe = enc.urlSafe).replace("=", "")
        of ENCODING_HEX: 
            result = result.toHex().toLowerAscii()
        of ENCODING_ROT:
            var s = ""
            for c in result: 
                s &= char((int(c) + enc.key) and 0xFF)
            result = s
        of ENCODING_XOR:
            var s = ""
            for c in result: 
                s &= char(int(c) xor enc.key)
            result = s

proc pickLine(s: string, previewSeed: int): string =
    let lines = s.splitLines().filterIt(it.strip().len() > 0)
    if lines.len() == 0: return ""
    if lines.len() == 1: return lines[0]
    return lines[abs(hash(s) xor previewSeed) mod lines.len()]

proc previewQueryParams(pairs: seq[KeyValue], previewSeed: int): string =
    var parts: seq[string]
    for pair in pairs:
        let key = pair.key.toString()
        let value = pair.value.toString().pickLine(previewSeed)
        if key.len() > 0: parts.add(key & "=" & value)
    if parts.len() > 0: result = "?" & parts.join("&")

proc previewEndpoint(buf: openArray[char], previewSeed: int): string =
    let line = buf.toString().pickLine(previewSeed)
    if line.len() > 0: return line
    return "/"

proc previewLine(lines: var seq[PreviewLine], segments: varargs[tuple[text: string, color: ImVec4]]) =
    var line: PreviewLine
    for seg in segments:
        if seg.text.len() > 0: line.add(seg)
    if line.len() > 0: lines.add(line)

proc previewHeader(lines: var seq[PreviewLine], pairs: seq[KeyValue], previewSeed: int) =
    for pair in pairs:
        let k = pair.key.toString()
        let v = pair.value.toString().pickLine(previewSeed)
        if k.len() > 0:
            lines.previewLine((k & ": " & v, CONSOLE_DEFAULT))

proc colorize(line: PreviewLine): PreviewLine =
    let ALPHANUMERIC = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

    for seg in line:
        var current = ""
        for c in seg.text:
            if c in {'#', '$'}:
                if current.len() > 0: result.add((current, seg.color))
                if c == '#': result.add(($ALPHANUMERIC[rand(ALPHANUMERIC.high)], CONSOLE_WARNING))
                else: result.add(($chr(ord('0') + rand(9)), CONSOLE_WARNING))
                current = ""
            else:
                current &= c
        if current.len() > 0: result.add((current, seg.color))

proc updatePreview(textarea: TextareaWidget, cache: var string, lines: seq[PreviewLine], seed: int) =
    var fingerprint = $seed
    for line in lines:
        for seg in line: fingerprint &= seg.text
        fingerprint &= "\n"
    
    if fingerprint == cache: 
        return
    cache = fingerprint
    textarea.clear()
    for line in lines:
        discard textarea.addItem(LOG_OUTPUT, colorize(line))

proc generateGetRequest(component: ListenerModalComponent) =
    var lines: seq[PreviewLine]
    let 
        endpoint = previewEndpoint(component.endpointsGET, component.previewSeed)
        query = previewQueryParams(component.queryParamsGET, component.previewSeed)
        placeholder = encode(PLACEHOLDER, component.heartbeatDataTransformation.encodings)
        prepend = component.heartbeatDataTransformation.prepend.toString()
        append = component.heartbeatDataTransformation.append.toString()
        placementName = component.heartbeatDataTransformation.placementName.toString()
        userAgent = component.userAgentGET.toString().pickLine(component.previewSeed)

    case component.heartbeatDataTransformation.placement
    of PLACEMENT_HEADER:
        lines.previewLine(("GET " & endpoint & query & " HTTP/1.1", CONSOLE_DEFAULT))
        lines.previewLine(("User-Agent: " & userAgent, CONSOLE_DEFAULT))
        lines.previewHeader(component.reqHeadersGET, component.previewSeed)
        lines.previewLine((placementName & ": " & prepend, CONSOLE_DEFAULT), (placeholder, CONSOLE_INFO), (append, CONSOLE_DEFAULT))
    
    of PLACEMENT_QUERY:
        let packet = prepend & placeholder & append
        lines.previewLine(("GET " & endpoint & query & (if query.len() > 0: "&" else: "?") & placementName & "=" & packet & " HTTP/1.1", CONSOLE_DEFAULT))    
        lines.previewLine(("User-Agent: " & userAgent, CONSOLE_DEFAULT))
        lines.previewHeader(component.reqHeadersGET, component.previewSeed)
    
    of PLACEMENT_BODY:
        lines.previewLine(("GET " & endpoint & query & " HTTP/1.1", CONSOLE_DEFAULT))
        lines.previewLine(("User-Agent: " & userAgent, CONSOLE_DEFAULT))
        lines.previewHeader(component.reqHeadersGET, component.previewSeed)
        lines.previewLine((prepend, CONSOLE_DEFAULT), (placeholder, CONSOLE_INFO), (append, CONSOLE_DEFAULT))

    component.reqPreviewGET.updatePreview(component.previewCacheGETReq, lines, component.previewSeed)

proc generateGetResponse(component: ListenerModalComponent) =
    var lines: seq[PreviewLine]
    let 
        placeholder = encode(PLACEHOLDER, component.tasksDataTransformation.encodings)
        prepend = component.tasksDataTransformation.prepend.toString()
        append = component.tasksDataTransformation.append.toString()

    lines.previewLine(("HTTP/1.1 200 OK", CONSOLE_DEFAULT))
    lines.previewHeader(component.respHeadersGET, component.previewSeed)
    lines.previewLine((prepend, CONSOLE_DEFAULT), (placeholder, CONSOLE_INFO), (append, CONSOLE_DEFAULT))

    component.respPreviewGET.updatePreview(component.previewCacheGETResp, lines, component.previewSeed)

proc generatePostRequest(component: ListenerModalComponent) =
    var lines: seq[PreviewLine]
    let 
        endpoint = previewEndpoint(component.endpointsPOST, component.previewSeed)
        query = previewQueryParams(component.queryParamsPOST, component.previewSeed)
        reqMethod = component.methods.toString()
        verb = if reqMethod.len() > 0: reqMethod.pickLine(component.previewSeed) else: "POST"
        placeholder = encode(PLACEHOLDER, component.resultDataTransformation.encodings)
        prepend = component.resultDataTransformation.prepend.toString()
        append = component.resultDataTransformation.append.toString()
        placementName = component.resultDataTransformation.placementName.toString()
        userAgent = component.userAgentPOST.toString().pickLine(component.previewSeed)

    case component.resultDataTransformation.placement
    of PLACEMENT_HEADER:
        lines.previewLine((verb & " " & endpoint & query & " HTTP/1.1", CONSOLE_DEFAULT))
        lines.previewLine(("User-Agent: " & userAgent, CONSOLE_DEFAULT))
        lines.previewHeader(component.reqHeadersPOST, component.previewSeed)
        lines.previewLine((placementName & ": " & prepend, CONSOLE_DEFAULT), (placeholder, CONSOLE_INFO), (append, CONSOLE_DEFAULT))
    
    of PLACEMENT_BODY:
        lines.previewLine((verb & " " & endpoint & query & " HTTP/1.1", CONSOLE_DEFAULT))
        lines.previewLine(("User-Agent: " & userAgent, CONSOLE_DEFAULT))
        lines.previewHeader(component.reqHeadersPOST, component.previewSeed)
        lines.previewLine((prepend, CONSOLE_DEFAULT), (placeholder, CONSOLE_INFO), (append, CONSOLE_DEFAULT))
    
    of PLACEMENT_QUERY:
        let packet = prepend & placeholder & append
        lines.previewLine((verb & " " & endpoint & query & (if query.len() > 0: "&" else: "?") & placementName & "=" & packet & " HTTP/1.1", CONSOLE_DEFAULT))
        lines.previewLine(("User-Agent: " & userAgent, CONSOLE_DEFAULT))
        lines.previewHeader(component.reqHeadersPOST, component.previewSeed)
    
    component.reqPreviewPOST.updatePreview(component.previewCachePOSTReq, lines, component.previewSeed)

proc generatePostResponse(component: ListenerModalComponent) =
    var lines: seq[PreviewLine]
    
    lines.previewLine(("HTTP/1.1 200 OK", CONSOLE_DEFAULT))
    lines.previewHeader(component.respHeadersPOST, component.previewSeed)
    let body = component.respBody.toString()
    if body.len() > 0: lines.previewLine((body, CONSOLE_DEFAULT))

    component.respPreviewPOST.updatePreview(component.previewCachePOSTResp, lines, component.previewSeed)

#[
    Draw
]#
proc draw*(component: ListenerModalComponent): UIListener =
    let textSpacing = igGetStyle().ItemSpacing.x
    let shuffleWidth = igCalcTextSize("(?)".cstring, nil, false, 0.0f).x + igGetStyle().ItemSpacing.x
    let modalLabel = if component.editingListener.isNil: "Start Listener" else: "Edit Listener"
    let buttonLabel = if component.editingListener.isNil: "Start" else: "Save"

    # Center modal
    let vp = igGetMainViewport()
    var center = ImGuiViewport_GetCenter(vp)
    igSetNextWindowPos(center, ImGuiCond_Appearing.int32, vec2(0.5f, 0.5f))

    let modalWidth = max(700.0f, vp.Size.x * 0.3)
    let modalHeight = if component.profileSettingsOpen and cast[ListenerType](component.protocol) != LISTENER_SMB: max(1000.0f, vp.Size.y * 0.5) else: 0.0f

    igSetNextWindowSize(vec2(modalWidth, modalHeight), ImGuiCond_Always.int32)
    let previewHeight = 8.0f * igGetTextLineHeightWithSpacing()

    var show = true
    if igBeginPopupModal(modalLabel.cstring, addr show, ImGuiWindowFlags_NoResize.int32 or ImGui_WindowFlags_NoScrollbar.int32):
        defer: igEndPopup()

        var disableStart = false

        # Listener name
        igText("Name:             ")
        igSameLine(0.0f, textSpacing)
        var availableSize = igGetContentRegionAvail()
        igSetNextItemWidth(availableSize.x)
        igInputText("##InputName", cast[cstring](addr component.name[0]), 256, ImGui_InputTextFlags_None .int32, nil, nil)

        # Listener protocol/type dropdown selection
        igText("Protocol:         ")
        igSameLine(0.0f, textSpacing)
        availableSize = igGetContentRegionAvail()
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

                # Help URL
                igTextDisabled("For more information about network profiles, check the")
                igSameLine(0.0f, textSpacing)
                igTextLinkOpenURL("documentation", "https://github.com/jakobfriedl/conquest/blob/main/docs/3-PROFILE.md")

                igDummy(vec2(0.0f, 10.0f))

                # Import/Export buttons
                availableSize = igGetContentRegionAvail()            
                if igButton("Import", vec2(availableSize.x * 0.5 - textSpacing * 0.5, 0.0f)):
                    let path = callDialogFileOpen("Load Profile", "", [("*.toml", "*.toml")])
                    if path.len() != 0: 
                        component.setProfile(parseString(readFile(path)))

                igSameLine(0.0f, textSpacing)

                if igButton("Export", vec2(availableSize.x * 0.5 - textSpacing * 0.5, 0.0f)):
                    let path = callDialogFileSave("Save Profile", component.name.toString() & ".toml")
                    if path.len() != 0: 
                        writeFile(path, component.toTomlProfile())

                igDummy(vec2(0.0f, 10.0f))

                # Profile settings
                if igBeginTabBar("##Tabs", ImGuiTabBarFlags_None.int32):
                    defer: igEndTabBar()

                    availableSize = igGetContentRegionAvail()
                    let contentHeight = availableSize.y - igGetFrameHeightWithSpacing() - 20.0f

                    # Tab 1: Agent GET Request: Heartbeat
                    if igBeginTabItem(fmt"GET {ICON_FA_ARROW_RIGHT} Heartbeat".cstring, nil, ImGuiTabBarFlags_None.int32):
                        defer: igEndTabItem()
                        discard igBeginChild_Str("##Tab1Scroll", vec2(0, contentHeight), ImGuiChildFlags_None.int32, ImGuiWindowFlags_None.int32)
                        defer: igEndChild()
                        igDummy(vec2(0.0f, 8.0f))

                        igText("User-Agent: ")
                        igMultilineInputFitted("##http-get.user-agent", component.userAgentGET, "User-Agent for GET requests.\nWhen multiple newline-separated user agents are specified, a random one is chosen for each request.")

                        igText("Endpoints:  ")
                        igMultilineInputFitted("##http-get.endpoints", component.endpointsGET, "Endpoints for GET requests.\nWhen multiple newline-separated endpoints are specified, a random one is chosen for each request.")

                        igDummy(vec2(0.0f, 10.0f))
                        igSeparatorTextWithHelpmarker("Request Headers", "Headers for GET requests.\n\nRandomization:\n - #: Random alphanumeric character\n - $: Random digit\n - Multiple newline-separated values: a random value is chosen for each request.")
                        component.drawKeyValueSetting("http-get.agent.headers", component.reqHeadersGET)

                        igDummy(vec2(0.0f, 10.0f))
                        igSeparatorTextWithHelpmarker("Query Parameters", "Query parameters for GET requests.\n\nRandomization:\n - #: Random alphanumeric character\n - $: Random digit\n - Multiple newline-separated values: a random value is chosen for each request.")
                        component.drawKeyValueSetting("http-get.agent.parameters", component.queryParamsGET)

                        igDummy(vec2(0.0f, 10.0f))
                        igSeparatorTextWithHelpmarker("Data Transformation: Heartbeat", "Defines how the heartbeat packet is transformed and placed in the GET request.\n\nPlacement: Location of the binary packet in the request (header, query parameter, or body).\nEncoding: Encoding applied to the packet (base64, hex, rot, xor). Multiple encodings are applied in order from top to bottom.\nPrepend/Append: Strings added before/after the packet in the request.")
                        component.drawDataTransformation("http-get.agent.heartbeat", component.heartbeatDataTransformation)

                        igDummy(vec2(0.0f, 10.0f))
                        igSeparatorTextEx(igGetID_Str("##PreviewGETReq"), "Preview".cstring, nil, shuffleWidth)
                        igSameLine(0.0f, textSpacing)
                        if igSmallButton(ICON_FA_SHUFFLE & "##ShuffleGETReq"): 
                            inc component.previewSeed
                        generateGetRequest(component)
                        availableSize = igGetContentRegionAvail()
                        component.reqPreviewGET.draw(vec2(availableSize.x, previewHeight))

                    # Tab 2: Server GET Response: Tasks
                    if igBeginTabItem(fmt"GET {ICON_FA_ARROW_LEFT} Tasks".cstring, nil, ImGuiTabBarFlags_None.int32):
                        defer: igEndTabItem()
                        discard igBeginChild_Str("##Tab2Scroll", vec2(0, contentHeight), ImGuiChildFlags_None.int32, ImGuiWindowFlags_None.int32)
                        defer: igEndChild()
                        igDummy(vec2(0.0f, 8.0f))

                        igDummy(vec2(0.0f, 10.0f))
                        igSeparatorTextWithHelpmarker("Response Headers", "Headers for GET responses.\n\nRandomization:\n - #: Random alphanumeric character\n - $: Random digit\n - Multiple newline-separated values: a random value is chosen for each response.")
                        component.drawKeyValueSetting("http-get.server.headers", component.respHeadersGET)

                        igDummy(vec2(0.0f, 10.0f))
                        igSeparatorTextWithHelpmarker("Data Transformation: Tasks", "Defines how the task packet is transformed and placed in the GET response.\n\nPlacement: Location of the binary packet in the response (header, query parameter, or body).\nEncoding: Encoding applied to the packet (base64, hex, rot, xor). Multiple encodings are applied in order from top to bottom.\nPrepend/Append: Strings added before/after the packet in the response.")
                        component.drawDataTransformation("http-get.server.output", component.tasksDataTransformation)

                        igDummy(vec2(0.0f, 10.0f))
                        igSeparatorTextEx(igGetID_Str("##PreviewGETResp"), "Preview".cstring, nil, shuffleWidth)
                        igSameLine(0.0f, textSpacing)
                        if igSmallButton(ICON_FA_SHUFFLE & "##ShuffleGETResp"): 
                            inc component.previewSeed
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
                        igMultilineInputFitted("##http-post.user-agent", component.userAgentPOST, "User-Agent for POST requests.\nWhen multiple newline-separated user agents are specified, a random one is chosen for each request.")

                        igText("Endpoints:       ")
                        igMultilineInputFitted("##http-post.endpoints", component.endpointsPOST, "Endpoints for POST requests.\nWhen multiple newline-separated endpoints are specified, a random one is chosen for each request.")

                        igText("Request Methods: ")
                        igMultilineInputFitted("##http-post.request-methods", component.methods, "Request methods used for POST requests.\nWhen multiple newline-separated HTTP verbs are specified, a random one is chosen for each request. Example:\nPOST\nPUT\nGET")

                        igDummy(vec2(0.0f, 10.0f))
                        igSeparatorTextWithHelpmarker("Request Headers", "Headers for POST requests.\n\nRandomization:\n - #: Random alphanumeric character\n - $: Random digit\n - Multiple newline-separated values: a random value is chosen for each request.")
                        component.drawKeyValueSetting("http-post.agent.headers", component.reqHeadersPOST)

                        igDummy(vec2(0.0f, 10.0f))
                        igSeparatorTextWithHelpmarker("Query Parameters", "Query parameters for POST requests.\n\nRandomization:\n - #: Random alphanumeric character\n - $: Random digit\n - Multiple newline-separated values: a random value is chosen for each request.")
                        component.drawKeyValueSetting("http-post.agent.parameters", component.queryParamsPOST)

                        igDummy(vec2(0.0f, 10.0f))
                        igSeparatorTextWithHelpmarker("Data Transformation: Task Results & Registration", "Defines how the task result/registration packet is transformed and placed in the POST request.\n\nPlacement: Location of the binary packet in the request (header, query parameter, or body).\nEncoding: Encoding applied to the packet (base64, hex, rot, xor). Multiple encodings are applied in order from top to bottom.\nPrepend/Append: Strings added before/after the packet in the request.")
                        component.drawDataTransformation("http-post.agent.output", component.resultDataTransformation)

                        igDummy(vec2(0.0f, 10.0f))
                        igSeparatorTextEx(igGetID_Str("##PreviewPOSTReq"), "Preview".cstring, nil, shuffleWidth)
                        igSameLine(0.0f, textSpacing)
                        if igSmallButton(ICON_FA_SHUFFLE & "##ShufflePOSTReq"): 
                            inc component.previewSeed
                        generatePostRequest(component)
                        availableSize = igGetContentRegionAvail()
                        component.reqPreviewPOST.draw(vec2(availableSize.x, previewHeight))

                    # Tab 4: Server POST Response
                    if igBeginTabItem(fmt"POST {ICON_FA_ARROW_LEFT} Response".cstring, nil, ImGuiTabBarFlags_None.int32):
                        defer: igEndTabItem()
                        discard igBeginChild_Str("##Tab4Scroll", vec2(0, contentHeight), ImGuiChildFlags_None.int32, ImGuiWindowFlags_None.int32)
                        defer: igEndChild()
                        igDummy(vec2(0.0f, 8.0f))

                        igDummy(vec2(0.0f, 10.0f))
                        igSeparatorTextWithHelpmarker("Response Headers", "Headers for POST responses.\n\nRandomization:\n - #: Random alphanumeric character\n - $: Random digit\n - Multiple newline-separated values: a random value is chosen for each response.")
                        component.drawKeyValueSetting("http-post.server.headers", component.respHeadersPOST)

                        igDummy(vec2(0.0f, 10.0f))
                        igSeparatorTextWithHelpmarker("Response Body", "Static response body returned by the server for POST requests.\n\nRandomization:\n - #: Random alphanumeric character\n - $: Random digit")
                        availableSize = igGetContentRegionAvail()
                        igInputTextMultiline("##http-post.server.output", cast[cstring](addr component.respBody[0]), MAX_INPUT_LENGTH, vec2(availableSize.x, 3.0f * igGetTextLineHeightWithSpacing()), ImGui_InputTextFlags_None.int32, nil, nil)

                        igDummy(vec2(0.0f, 10.0f))
                        igSeparatorTextEx(igGetID_Str("##PreviewPOSTResp"), "Preview".cstring, nil, shuffleWidth)
                        igSameLine(0.0f, textSpacing)
                        if igSmallButton(ICON_FA_SHUFFLE & "##ShufflePOSTResp"): 
                            inc component.previewSeed
                        generatePostResponse(component)
                        availableSize = igGetContentRegionAvail()
                        component.respPreviewPOST.draw(vec2(availableSize.x, previewHeight))

        igDummy(vec2(0.0f, 10.0f))

        # Buttons
        availableSize = igGetContentRegionAvail()
        igBeginDisabled(disableStart or component.name.toString.len() <= 0)
        if igButton(buttonLabel.cstring, vec2(availableSize.x * 0.5 - textSpacing * 0.5, 0.0f)):

            let uuid = if component.editingListener.isNil: generateUUID() else: component.editingListener.listenerId
            result = UIListener(
                listenerId: uuid,
                name: component.name.toString(),
                listenerType: cast[ListenerType](component.protocol)
            )

            # Process callback settings
            case result.listenerType:
            of LISTENER_HTTP:
                var hosts: string = ""
                let
                    callbackHosts = component.callbackHosts.toString()
                    bindAddress = component.bindAddress.toString()
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

                result.hosts = hosts
                result.address = bindAddress
                result.port = bindPort
                result.profile = component.toTomlProfile()

            of LISTENER_SMB:
                result.pipe = "\\\\.\\pipe\\" & component.pipe.toString()

            component.resetModalValues()
            igCloseCurrentPopup()

        igEndDisabled()
        igSameLine(0.0f, textSpacing)

        if igButton("Close", vec2(availableSize.x * 0.5 - textSpacing * 0.5, 0.0f)):
            component.resetModalValues()
            igCloseCurrentPopup()