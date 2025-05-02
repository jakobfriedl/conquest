import prologue

# /agent/register
proc agentRegister*(ctx: Context) {.async.} =
  
  let body: JsonNode = ctx.request.body().parseJson()
  echo body

  resp jsonResponse(body, Http200)
  


# /agent/{uuid}/tasks
proc agentTasks*(ctx: Context) {.async.} =
  resp "<h1>Agent Tasks</h1>"

# /agent/{uuid}/results
proc agentResults*(ctx: Context) {.async.} =
  resp "<h1>Agent Results</h1>"
