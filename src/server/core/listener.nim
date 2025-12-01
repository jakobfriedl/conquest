import strformat, strutils, terminal, tables
import mummy, mummy/routers

import ../api/routes
import ../db/database
import ../core/[logger, websocket]
import ../../common/[types, profile]

proc serve(listener: Listener) {.thread.} = 
    try: 
        listener.server.serve(Port(listener.port), listener.address)
    except Exception:
        discard 

proc listenerStart*(cq: Conquest, listener: UIListener) = 
    try:
        var l: Listener
        case listener.listenerType 
        of LISTENER_HTTP:
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
            
            let server = newServer(router.toHandler(), maxBodyLen = 1024 * 1024 * 1024) 

            # Store listener in database
            l = Listener(
                server: server,
                listenerId: listener.listenerId,
                listenerType: LISTENER_HTTP,
                hosts: listener.hosts,
                address: listener.address,
                port: listener.port
            )

            # Start serving
            var thread: Thread[Listener]
            createThread(thread, serve, l)
            server.waitUntilReady()

            cq.threads[listener.listenerId] = thread

        of LISTENER_SMB: 
            l = Listener(
                listenerId: listener.listenerId, 
                listenerType: LISTENER_SMB,
                pipe: listener.pipe
            )

        cq.listeners[listener.listenerId] = l

        # Store listener in database
        if not cq.dbListenerExists(listener.listenerId.toUpperAscii): 
            if not cq.dbStoreListener(l):
                raise newException(CatchableError, "Failed to store listener in database.")

        cq.success("Started listener", fgGreen, fmt" {l.listenerId}.")
        cq.client.sendListener(l)
        cq.client.sendEventlogItem(LOG_SUCCESS_SHORT, fmt"Started listener {l.listenerId}.")

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

    