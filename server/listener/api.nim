import prologue

import ../types

proc index*(ctx: Context) {.async.} = 
    resp "Index"
    
proc agentRegister*(ctx: Context) {.async.} = 
    resp "Register"

proc addTasks*(ctx: Context) {.async.} = 
    
    let name = ctx.getPathParams("name")
    
    resp name
