import strformat, strutils, sequtils, checksums/sha1, nanoid, terminal
import prologue

import ./api
import ../[types, utils]
import ../db/database

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
    # if not validateIPv4Address(host): 
    #     cq.writeLine(fgRed, styleBright, fmt"Invalid IPv4 IP address: {ip}.")
    #     return
    if not validatePort(portStr):
        cq.writeLine(fgRed, styleBright, fmt"[-] Invalid port number: {portStr}")
        return

    let port = portStr.parseInt

    # Create new listener
    let 
        name: string = generate(alphabet=join(toSeq('A'..'Z'), ""), size=8)
        listenerSettings = newSettings(
            appName = name,
            debug = false,
            address = "",               # For some reason, the program crashes when the ip parameter is passed to the newSettings function
            port = Port(port)           # As a result, I will hardcode the listener to be served on all interfaces (0.0.0.0) by default
        )                               # TODO: fix this issue and start the listener on the address passed as the HOST parameter
    
    var listener = newApp(settings = listenerSettings)

    # Define API endpoints
    listener.post("{listener}/register", api.register)
    listener.get("{listener}/{agent}/tasks", api.getTasks)
    listener.post("{listener}/{agent}/results", api.postResults)
    listener.registerErrorHandler(Http404, api.error404)

    # Store listener in database
    var listenerInstance = newListener(name, host, port)
    if not cq.dbStoreListener(listenerInstance):
        return

    # Start serving
    try:
        discard listener.runAsync() 
        cq.add(listenerInstance.name, listenerInstance)
        cq.writeLine(fgGreen, "[+] ", resetStyle, "Started listener", fgGreen, fmt" {name} ", resetStyle, fmt"on port {portStr}.")
    except CatchableError as err: 
        cq.writeLine(fgRed, styleBright, "[-] Failed to start listener: ", getCurrentExceptionMsg())

proc restartListeners*(cq: Conquest) = 
    let listeners: seq[Listener] = cq.dbGetAllListeners()
    
    # Restart all active listeners that are stored in the database
    for l in listeners: 
        let 
            settings = newSettings(
                appName = l.name,
                debug = false,
                address = "",
                port = Port(l.port)
            )
            listener = newApp(settings = settings)

        # Define API endpoints
        listener.post("{listener}/register", api.register)
        listener.get("{listener}/{agent}/tasks", api.getTasks)
        listener.post("{listener}/{agent}/results", api.postResults)
        listener.registerErrorHandler(Http404, api.error404)
        
        try:
            discard listener.runAsync() 
            cq.add(l.name, l)
            cq.writeLine(fgGreen, "[+] ", resetStyle, "Restarted listener", fgGreen, fmt" {l.name} ", resetStyle, fmt"on port {$l.port}.")
        except CatchableError as err: 
            cq.writeLine(fgRed, styleBright, "[-] Failed to restart listener: ", getCurrentExceptionMsg())
        
        # Delay before starting serving another listener to avoid crashing the application
        waitFor sleepAsync(10)

    cq.writeLine("")

proc listenerStop*(cq: Conquest, name: string) = 
        
    if not cq.dbDeleteListenerByName(name.toUpperAscii): 
        cq.writeLine(fgRed, styleBright, "[-] Failed to stop listener: ", getCurrentExceptionMsg())
        return

    cq.delListener(name)
    cq.writeLine(fgGreen, "[+] ", resetStyle, "Stopped listener ", fgGreen, name.toUpperAscii, resetStyle, ".")
    