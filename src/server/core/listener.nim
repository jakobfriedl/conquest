import strformat, strutils, terminal, tables, os
import mummy

import ../api/routes
import ../db/database
import ../core/[logger, websocket]
import ../../common/profile
import ../../types/[common, server]

# Required to access mummys request.server field, which allows us to map servers to the profile they use
import std/importutils
privateAccess(RequestObj)
var serverProfiles: Table[pointer, Profile]

# Channel for serve thread to signal bind failure back to listenerStart.
var errorChannel: Channel[string]

proc openErrorChannel*() =
    errorChannel.open(1)

proc serve(listener: Listener) {.thread.} =
    try:
        listener.server.serve(Port(listener.port), listener.address)
    except CatchableError as err:
        discard errorChannel.trySend(err.msg.splitLines()[^1].strip())

proc handler(request: Request) {.gcsafe.} =
    {.cast(gcsafe).}:
        let profile = serverProfiles.getOrDefault(cast[pointer](request.server))    # Retrieve profile settings from the profiles table 
        if profile.isNil:
            routes.error404(request)
            return

        let path = request.path
        let verb = request.httpMethod

        for endpoint in profile.getArray("http-get.endpoints"):
            if path == endpoint.getStringValue():
                if verb == "GET":
                    routes.httpGet(request, profile)
                else:
                    routes.error405(request)
                return

        var postMethods = @["POST"]
        let configuredMethods = profile.getArray("http-post.request-methods")
        if configuredMethods.len() > 0:
            postMethods.setLen(0)
            for m in configuredMethods:
                postMethods.add(m.getStringValue())

        for endpoint in profile.getArray("http-post.endpoints"):
            if path == endpoint.getStringValue():
                if verb in postMethods:
                    routes.httpPost(request, profile)
                else:
                    routes.error405(request)
                return

        routes.error404(request)

proc listenerStart*(cq: Conquest, listener: UIListener) =
    try:
        var l: Listener

        case listener.listenerType
        of LISTENER_HTTP:
            let server = newServer(handler, maxBodyLen = 1024 * 1024 * 1024)
            serverProfiles[cast[pointer](server)] = parseString(listener.profile)   # Create table entry to handle profile overwrites

            l = Listener(
                server: server,
                listenerId: listener.listenerId,
                name: listener.name,
                listenerType: LISTENER_HTTP,
                hosts: listener.hosts,
                address: listener.address,
                port: listener.port,
                profile: listener.profile
            )

            var thread: Thread[Listener]
            createThread(thread, serve, l)

            # Drain stale messages, then poll up to 300ms for a bind failure.
            while errorChannel.tryRecv().dataAvailable: discard
            for _ in 0 ..< 3:   # Wait for 300ms
                sleep(100)
                let r = errorChannel.tryRecv()
                if r.dataAvailable:
                    raise newException(CatchableError, r.msg)

        of LISTENER_SMB:
            l = Listener(
                listenerId: listener.listenerId,
                name: listener.name,
                listenerType: LISTENER_SMB,
                pipe: listener.pipe
            )

        cq.listeners[listener.listenerId] = l

        # Store listener in database
        if not cq.dbListenerExists(listener.listenerId):
            if not cq.dbStoreListener(l):
                # Stop serving
                if l.listenerType == LISTENER_HTTP: 
                    try: l.server.close() 
                    except: discard
                cq.listeners.del(listener.listenerId)
                raise newException(CatchableError, "Failed to store listener in database")

        cq.success("Started listener", fgGreen, fmt""" "{listener.name}" ({l.listenerId}).""")
        cq.sendListener(l)
        cq.sendEventlogItem(LOG_SUCCESS_SHORT, fmt"""Started listener "{listener.name}" ({l.listenerId}).""")

    except CatchableError as err:
        cq.error("Failed to start listener: ", err.msg)
        cq.sendEventlogItem(LOG_ERROR_SHORT, fmt"Failed to start listener: {err.msg}.")

proc listenerStop*(cq: Conquest, name: string) =
    # Verify that listener exists
    if not cq.dbListenerExists(name):
        cq.error(fmt"Listener {name} does not exist.")
        return

    # Remove entry from database to prevent server restart
    if not cq.dbDeleteListenerByName(name):
        cq.error("Failed to stop listener: ", getCurrentExceptionMsg())
        return

    # Stop listener
    if name in cq.listeners:
        let listener = cq.listeners[name]
        case listener.listenerType:
        of LISTENER_HTTP:
            serverProfiles.del(cast[pointer](listener.server))
            try: listener.server.close()
            except: discard
        of LISTENER_SMB: discard
        cq.listeners.del(name)

    cq.sendListenerRemove(name)
    cq.sendEventlogItem(LOG_SUCCESS_SHORT, fmt"Stopped listener {name}.")
    cq.success("Stopped listener ", fgGreen, name, resetStyle, ".")
