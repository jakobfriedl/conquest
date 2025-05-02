import prologue
import logging
import uuids
import strformat
import std/asynchttpserver

proc hello*(ctx: Context) {.async.} = 
  resp "Test"

# /client/listener
proc listenerList*(ctx: Context) {.async.} =

  # JSON Response
  let response = %*{"message": "Ok"}
  resp jsonResponse(response)

# /client/listener/create
proc listenerCreate*(ctx: Context) {.async.} =
  
  # Handle POST parameters (Port, IP)

  # Create listener with random UUID 
  let 
    name: string = $genUUID() 
    listenerSettings = newSettings(
      appName = name,
      debug = false,
      address = "127.0.0.1",
      port = Port(443),
      secretKey = name
    )
  var listener = newApp(settings=listenerSettings)

  proc listenerHandler(req: NativeRequest): Future[void] {.gcsafe.}  = 
    req.respond(Http200, name)

  discard listener.serveAsync(listenerHandler)
  logging.info(fmt"Listener {name} created.")

  resp fmt"Listener {name} created.<br>Listening on <a href=http://{listenerSettings.address}:{listenerSettings.port}>{listenerSettings.address}:{listenerSettings.port}</a>"

# /client/listener/{uuid}/delete
proc listenerDelete*(ctx: Context) {.async.} =
  resp "<h2>Listener Deleted</h2>"

# /client/agent
proc agentList*(ctx: Context) {.async.} =
  resp "<h1>Agent List</h1>"

# /client/agent/build
proc agentCreate*(ctx: Context) {.async.} =
  resp "<h1>Agent Create</h1>"
