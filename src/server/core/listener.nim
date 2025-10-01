import strformat, strutils, terminal
import mummy, mummy/routers
import parsetoml

import ../globals
import ../utils
import ../api/routes
import ../db/database
import ../core/logger
import ../../common/[types, utils, profile]
import ../websocket

proc serve(listener: Listener) {.thread.} = 
    try: 
        listener.server.serve(Port(listener.port), listener.address)
    except Exception as err:
        discard 

proc listenerStart*(cq: Conquest, name: string, host: string, port: int, protocol: Protocol) = 
    try:
        # Create new listener
        var router: Router
        router.notFoundHandler = routes.error404
        router.methodNotAllowedHandler = routes.error405
        
        # Define API endpoints based on C2 profile
        # GET requests
        for endpoint in cq.profile.getArray("http-get.endpoints"): 
            router.addRoute("GET", endpoint.getStringValue(), routes.httpGet)
        
        # POST requests
        var postMethods: seq[string]
        for reqMethod in cq.profile.getArray("http-post.request-methods"): 
            postMethods.add(reqMethod.getStringValue())

        # Default method is POST
        if postMethods.len == 0: 
            postMethods = @["POST"]

        for endpoint in cq.profile.getArray("http-post.endpoints"): 
            for httpMethod in postMethods:
                router.addRoute(httpMethod, endpoint.getStringValue(), routes.httpPost)
        
        let server = newServer(router.toHandler()) 

        # Store listener in database
        var listener = Listener(
            server: server,
            listenerId: name,
            address: host,
            port: port,
            protocol: protocol
        )

        # Start serving
        var thread: Thread[Listener]
        createThread(thread, serve, listener)
        server.waitUntilReady()

        cq.listeners[name] = listener
        cq.threads[name] = thread

        if not cq.dbListenerExists(name.toUpperAscii): 
            if not cq.dbStoreListener(listener):
                raise newException(CatchableError, "Failed to store listener in database.")

        cq.success("Started listener", fgGreen, fmt" {name} ", resetStyle, fmt"on {host}:{$port}.")
        cq.client.sendListener(listener)
        cq.client.sendEventlogItem(LOG_SUCCESS_SHORT, fmt"Started listener {name} on {host}:{$port}.")

    except CatchableError as err: 
        cq.error("Failed to start listener: ", err.msg)
        cq.client.sendEventlogItem(LOG_ERROR_SHORT, fmt"Failed to start listener: {err.msg}.")

# Remove listener from database, preventing automatic startup on server restart
proc listenerStop*(cq: Conquest, name: string) = 
        
    # Check if listener supplied via -n parameter exists in database
    if not cq.dbListenerExists(name.toUpperAscii): 
        cq.error(fmt"Listener {name.toUpperAscii} does not exist.")
        return

    # Remove database entry
    if not cq.dbDeleteListenerByName(name.toUpperAscii): 
        cq.error("Failed to stop listener: ", getCurrentExceptionMsg())
        return

    cq.listeners.del(name)
    cq.success("Stopped listener ", fgGreen, name.toUpperAscii, resetStyle, ".")
    
    # TODO: Shutdown listener without server restart. Since the listener is removed from the DB, agents connecting to it after it has been shutdown are not accepted
    # try: 
    #     cq.listeners[name].listener .server.close()
    #     joinThread(cq.listeners[name].thread)    
    # except: 
    #     cq.error("Failed to stop listener.")

    