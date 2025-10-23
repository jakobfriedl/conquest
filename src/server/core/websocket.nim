import times, json, base64, parsetoml, strformat, pixie
import stb_image/write as stbiw
import ./logger
import ../../common/[types, utils, event]
export sendHeartbeat, recvEvent

proc `%`*(agent: Agent): JsonNode =
    result = newJObject()
    result["agentId"] = %agent.agentId
    result["listenerId"] = %agent.listenerId
    result["username"] = %agent.username
    result["impersonationToken"] = %agent.impersonationToken
    result["hostname"] = %agent.hostname
    result["domain"] = %agent.domain
    result["ipInternal"] = %agent.ipInternal
    result["ipExternal"] = %agent.ipExternal
    result["os"] = %agent.os
    result["process"] = %agent.process
    result["pid"] = %agent.pid
    result["elevated"] = %agent.elevated
    result["sleep"] = %agent.sleep
    result["jitter"] = %agent.jitter
    result["modules"] = %agent.modules
    result["firstCheckin"] = %agent.firstCheckin
    result["latestCheckin"] = %agent.latestCheckin

proc `%`*(listener: Listener): JsonNode =
    result = newJObject()
    result["listenerId"] = %listener.listenerId
    result["hosts"] = %listener.hosts
    result["address"] = %listener.address
    result["port"] = %listener.port 
    result["protocol"] = %listener.protocol

#[
    Server -> Client
]#
proc sendPublicKey*(client: WsConnection, publicKey: Key) = 
    let event = Event(
        eventType: CLIENT_KEY_EXCHANGE,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "publicKey": encode(Bytes.toString(publicKey))
        }
    )
    if client != nil: 
        client.ws.sendEvent(event, client.sessionKey)

proc sendProfile*(client: WsConnection, profile: Profile) = 
    let event = Event(
        eventType: CLIENT_PROFILE,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "profile": profile.toTomlString()
        }
    )
    if client != nil: 
        client.ws.sendEvent(event, client.sessionKey)

proc sendEventlogItem*(client: WsConnection, logType: LogType, message: string) = 
    let event = Event(
        eventType: CLIENT_EVENTLOG_ITEM,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "logType": cast[uint8](logType),
            "message": message
        }
    )

    # Log event
    let timestamp = event.timestamp.fromUnix().local().format("dd-MM-yyyy HH:mm:ss")
    log(fmt"[{timestamp}]{$logType}{message}")

    if client != nil: 
        client.ws.sendEvent(event, client.sessionKey)

proc sendAgent*(client: WsConnection, agent: Agent) = 
    let event = Event(
        eventType: CLIENT_AGENT_ADD, 
        timestamp: now().toTime().toUnix(),
        data: %agent
    )
    if client != nil: 
        client.ws.sendEvent(event, client.sessionKey)

proc sendListener*(client: WsConnection, listener: Listener) =
    let event = Event(
        eventType: CLIENT_LISTENER_ADD,
        timestamp: now().toTime().toUnix(),
        data: %listener
    )
    if client != nil: 
        client.ws.sendEvent(event, client.sessionKey)

proc sendAgentCheckin*(client: WsConnection, agentId: string) = 
    let event = Event(
        eventType: CLIENT_AGENT_CHECKIN,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "agentId": agentId
        }
    )
    if client != nil: 
        client.ws.sendEvent(event, client.sessionKey)

proc sendAgentPayload*(client: WsConnection, bytes: seq[byte]) =
    let event = Event(
        eventType: CLIENT_AGENT_PAYLOAD, 
        timestamp: now().toTime().toUnix(),
        data: %*{
            "payload": encode(bytes)
        }
    )
    
    if client != nil: 
        client.ws.sendEvent(event, client.sessionKey)

proc sendConsoleItem*(client: WsConnection, agentId: string, logType: LogType, message: string) = 
    let event = Event(
        eventType: CLIENT_CONSOLE_ITEM,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "agentId": agentId,
            "logType": cast[uint8](logType),
            "message": message
        }
    )

    # Log agent console item 
    let timestamp = event.timestamp.fromUnix().local().format("dd-MM-yyyy HH:mm:ss")
    if logType != LOG_OUTPUT: 
        log(fmt"[{timestamp}]{$logType}{message}", agentId)
    else: 
        log(message, agentId)

    if client != nil: 
        client.ws.sendEvent(event, client.sessionKey)

proc sendBuildlogItem*(client: WsConnection, logType: LogType, message: string) = 
    let event = Event(
        eventType: CLIENT_BUILDLOG_ITEM,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "logType": cast[uint8](logType),
            "message": message
        }
    )
    if client != nil: 
        client.ws.sendEvent(event, client.sessionKey)

proc createThumbnail(data: string, maxHeight: int = 1024, quality: int = 80): string =
    let img: Image = decodeImage(data)
    
    # Resize image
    let aspectRatio = img.width.float / img.height.float
    let
        height = min(maxHeight, img.height)
        width = int(height.float * aspectRatio)
    let thumbnail = img.resize(width, height)

    # Convert to JPEG image for smaller file size
    var rgbaData = newSeq[byte](width * height * 4)
    var i = 0
    for y in 0..<height:
        for x in 0..<width:
            let color = thumbnail[x, y]
            rgbaData[i] = color.r
            rgbaData[i + 1] = color.g
            rgbaData[i + 2] = color.b
            rgbaData[i + 3] = color.a
            i += 4
    
    return Bytes.toString(stbiw.writeJPG(width, height, 4, rgbaData, quality))

proc sendLoot*(client: WsConnection, loot: LootItem) = 
    let event = Event(
        eventType: CLIENT_LOOT_ADD,
        timestamp: now().toTime().toUnix(),
        data: %loot
    )
    if client != nil: 
        client.ws.sendEvent(event, client.sessionKey)

proc sendLootData*(client: WsConnection, loot: LootItem, data: string) = 
    let event = Event(
        eventType: CLIENT_LOOT_DATA,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "loot": %loot,
            "data": encode(data)
        }
    )
    if client != nil: 
        client.ws.sendEvent(event, client.sessionKey)

proc sendImpersonateToken*(client: WsConnection, agentId: string, username: string) = 
    let event = Event(
        eventType: CLIENT_IMPERSONATE_TOKEN,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "agentId": agentId,
            "username": username
        }
    )
    if client != nil: 
        client.ws.sendEvent(event, client.sessionKey)

proc sendRevertToken*(client: WsConnection, agentId: string) = 
    let event = Event(
        eventType: CLIENT_REVERT_TOKEN,
        timestamp: now().toTime().toUnix(),
        data: %*{
            "agentId": agentId
        }
    )
    if client != nil: 
        client.ws.sendEvent(event, client.sessionKey)