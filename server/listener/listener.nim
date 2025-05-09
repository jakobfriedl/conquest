import strformat, strutils, sequtils, checksums/sha1, nanoid, terminal, sugar
import prologue

import ./[api, utils]
import ../types
import ../db/database


proc listenerUsage*(console: Console) = 
    console.writeLine("""Manage, start and stop listeners.

Usage:
  listener [options] COMMAND

Commands:

  list             List all active listeners.
  start            Starts a new HTTP listener.
  stop             Stop an active listener.

Options:
  -h, --help""")

proc listenerList*(console: Console) = 
    let listeners = console.dbGetAllListeners()
    console.drawTable(listeners)

proc listenerStart*(console: Console, host: string, portStr: string) = 

    # Validate arguments
    # if not validateIPv4Address(host): 
    #     console.writeLine(fgRed, styleBright, fmt"Invalid IPv4 IP address: {ip}.")
    #     return
    if not validatePort(portStr):
        console.writeLine(fgRed, styleBright, fmt"[-] Invalid port number: {portStr}")
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
    listener.addRoute("/", api.index, @[HttpGet])
    listener.addRoute("/register", api.agentRegister, @[HttpPost])
    listener.addRoute("/{name}/tasks", api.addTasks, @[HttpGet, HttpPost])

    # Store listener in database
    let listenerInstance = newListener(name, host, port)
    if not console.dbStore(listenerInstance):
        return

    # Start serving
    try:
        discard listener.runAsync() 
        console.activeListeners.add(listener)
        inc console.listeners
        console.writeLine(fgGreen, "[+] ", resetStyle, "Started listener", fgGreen, fmt" {name} ", resetStyle, fmt"on port {portStr}.")
    except CatchableError as err: 
        console.writeLine(fgRed, styleBright, "[-] Failed to start listener: ", getCurrentExceptionMsg())

proc restartListeners*(console: Console) = 
    let listeners: seq[Listener] = console.dbGetAllListeners()
    
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
        listener.addRoute("/", api.index, @[HttpGet])
        listener.addRoute("/register", api.agentRegister, @[HttpPost])
        listener.addRoute("/{name}/tasks", api.addTasks, @[HttpGet, HttpPost])

        try:
            discard listener.runAsync() 
            console.activeListeners.add(listener)
            inc console.listeners
            console.writeLine(fgGreen, "[+] ", resetStyle, "Restarted listener", fgGreen, fmt" {l.name} ", resetStyle, fmt"on port {$l.port}.")
        except CatchableError as err: 
            console.writeLine(fgRed, styleBright, "[-] Failed to restart listener: ", getCurrentExceptionMsg())
        
        # Delay before starting serving another listener to avoid crashing the application
        waitFor sleepAsync(10)

    console.writeLine("")

proc listenerStop*(console: Console, name: string) = 
        
    if not console.dbDeleteListenerByName(name.toUpperAscii): 
        console.writeLine(fgRed, styleBright, "[-] Failed to stop listener: ", getCurrentExceptionMsg())
        return

    dec console.listeners
    console.writeLine(fgGreen, "[+] ", resetStyle, "Stopped listener ", fgGreen, fmt"{name.toUpperAscii}.")
    