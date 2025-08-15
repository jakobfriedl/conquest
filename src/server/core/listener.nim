import strformat, strutils, sequtils, terminal
import prologue, parsetoml
import sugar


import ../utils
import ../api/routes
import ../db/database
import ../../common/[types, utils, profile]

# Utility functions
proc delListener(cq: Conquest, listenerName: string) = 
    cq.listeners.del(listenerName)

proc add(cq: Conquest, listener: Listener) = 
    cq.listeners[listener.listenerId] = listener

#[
    Listener management
]#
proc listenerUsage*(cq: Conquest) = 
    cq.writeLine("""Manage, start and stop listeners.

Usage:
  listener [options] COMMAND

Commands:

  list             List all active listeners.
  start            Starts a new HTTP listener.
  stop             Stop an active listener.

Options:
  -h, --help""")

proc listenerList*(cq: Conquest) = 
    let listeners = cq.dbGetAllListeners()
    cq.drawTable(listeners)

proc listenerStart*(cq: Conquest, host: string, portStr: string) = 

    # Validate arguments
    if not validatePort(portStr):
        cq.writeLine(fgRed, styleBright, fmt"[-] Invalid port number: {portStr}")
        return

    let port = portStr.parseInt

    # Create new listener
    let 
        name: string = generateUUID() 
        listenerSettings = newSettings(
            appName = name,
            debug = false,
            address = "",               # For some reason, the program crashes when the ip parameter is passed to the newSettings function
            port = Port(port)           # As a result, I will hardcode the listener to be served on all interfaces (0.0.0.0) by default
        )                               # TODO: fix this issue and start the listener on the address passed as the HOST parameter
    
    var listener = newApp(settings = listenerSettings)

    # Define API endpoints based on C2 profile
    # GET requests
    for endpoint in cq.profile.getArray("http-get.endpoints"): 
        listener.addRoute(endpoint.getStr(), routes.httpGet)
    
    # POST requests
    var postMethods: seq[HttpMethod]
    for reqMethod in cq.profile.getArray("http-post.request-methods"): 
        postMethods.add(parseEnum[HttpMethod](reqMethod.getStr()))

    # Default method is POST
    if postMethods.len == 0: 
        postMethods = @[HttpPost]

    for endpoint in cq.profile.getArray("http-post.endpoints"): 
        listener.addRoute(endpoint.getStr(), routes.httpPost, postMethods)
    
    listener.registerErrorHandler(Http404, routes.error404)

    # Store listener in database
    var listenerInstance = Listener(
        listenerId: name,
        address: host,
        port: port,
        protocol: HTTP
    )
    if not cq.dbStoreListener(listenerInstance):
        return

    # Start serving
    try:
        discard listener.runAsync() 
        cq.add(listenerInstance)
        cq.writeLine(fgGreen, "[+] ", resetStyle, "Started listener", fgGreen, fmt" {name} ", resetStyle, fmt"on {host}:{portStr}.")
    except CatchableError as err: 
        cq.writeLine(fgRed, styleBright, "[-] Failed to start listener: ", err.msg)

proc restartListeners*(cq: Conquest) = 
    let listeners: seq[Listener] = cq.dbGetAllListeners()
    
    # Restart all active listeners that are stored in the database
    for l in listeners: 
        let 
            settings = newSettings(
                appName = l.listenerId,
                debug = false,
                address = "",
                port = Port(l.port)
            )
            listener = newApp(settings = settings)

        # Define API endpoints based on C2 profile
        # TODO: Store endpoints for already running listeners is DB (comma-separated) and use those values for restarts
        # GET requests
        for endpoint in cq.profile.getArray("http-get.endpoints"): 
            listener.get(endpoint.getStr(), routes.httpGet)
        
        # POST requests
        var postMethods: seq[HttpMethod]
        for reqMethod in cq.profile.getArray("http-post.request-methods"): 
            postMethods.add(parseEnum[HttpMethod](reqMethod.getStr()))

        # Default method is POST
        if postMethods.len == 0: 
            postMethods = @[HttpPost]

        for endpoint in cq.profile.getArray("http-post.endpoints"): 
            listener.addRoute(endpoint.getStr(), routes.httpPost, postMethods)
    
        listener.registerErrorHandler(Http404, routes.error404)
            
        try:
            discard listener.runAsync() 
            cq.add(l)
            cq.writeLine(fgGreen, "[+] ", resetStyle, "Restarted listener", fgGreen, fmt" {l.listenerId} ", resetStyle, fmt"on {l.address}:{$l.port}.")
        except CatchableError as err: 
            cq.writeLine(fgRed, styleBright, "[-] Failed to restart listener: ", err.msg)
        
        # Delay before starting serving another listener to avoid crashing the application
        waitFor sleepAsync(10)

    cq.writeLine("")

# Remove listener from database, preventing automatic startup on server restart
proc listenerStop*(cq: Conquest, name: string) = 
        
    # Check if listener supplied via -n parameter exists in database
    if not cq.dbListenerExists(name.toUpperAscii): 
        cq.writeLine(fgRed, styleBright, fmt"[-] Listener {name.toUpperAscii} does not exist.")
        return

    # Remove database entry
    if not cq.dbDeleteListenerByName(name.toUpperAscii): 
        cq.writeLine(fgRed, styleBright, "[-] Failed to stop listener: ", getCurrentExceptionMsg())
        return

    cq.delListener(name)
    cq.writeLine(fgGreen, "[+] ", resetStyle, "Stopped listener ", fgGreen, name.toUpperAscii, resetStyle, ".")
    