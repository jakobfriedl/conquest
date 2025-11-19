import mummy, terminal, parsetoml, tables
import strutils, strformat, base64

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

        of "body": 
            heartbeatString = request.body 

        else: discard 

        # Reverse data transformation to get raw heartbeat packet
        let heartbeat = cq.profile.reverseDataTransformation("http-get.agent.heartbeat", heartbeatString)

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
            let payload = cq.profile.applyDataTransformation("http-get.server.output", responseBytes)

            # Add headers, as defined in the team server profile 
            var headers: HttpHeaders
            for header, value in cq.profile.getTable("http-get.server.headers"):
                headers.add((header, value.getStringValue()))

            request.respond(200, headers = headers, body = payload)

            # Notify operator that agent collected tasks
            cq.client.sendConsoleItem(agentId, LOG_INFO, fmt"{$responseBytes.len} bytes sent.")
            cq.info(fmt"{$responseBytes.len} bytes sent.")

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

            of "body": 
                dataString = request.body

            else: discard 

            # Reverse data transformation
            let data = cq.profile.reverseDataTransformation("http-post.agent.output", dataString)

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