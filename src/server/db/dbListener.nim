import strformat, strutils, system, terminal, tiny_sqlite

import ../core/logger
import ../../common/types

# Utility functions 
proc stringToProtocol*(protocol: string): Protocol = 
    case protocol
    of "http": 
        return HTTP
    else: discard

#[
    Listener database functions
]#
proc dbStoreListener*(cq: Conquest, listener: Listener): bool = 

    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        conquestDb.exec("""
        INSERT INTO listeners (listenerId, hosts, address, port, protocol)
        VALUES (?, ?, ?, ?, ?);
        """, listener.listenerId, listener.hosts, listener.address, listener.port, $listener.protocol)

        conquestDb.close() 
    except: 
        cq.error(getCurrentExceptionMsg())
        return false
    
    return true

proc dbGetAllListeners*(cq: Conquest): seq[Listener] = 

    var listeners: seq[Listener] = @[]

    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        for row in conquestDb.iterate("SELECT listenerId, hosts, address, port, protocol FROM listeners;"):
            let (listenerId, hosts, address, port, protocol) = row.unpack((string, string, string, int, string))
            
            let l = Listener(
                listenerId: listenerId,
                hosts: hosts,
                address: address,
                port: port,
                protocol: stringToProtocol(protocol),
            )
            listeners.add(l)

        conquestDb.close()
    except: 
        cq.error(getCurrentExceptionMsg())

    return listeners

proc dbDeleteListenerByName*(cq: Conquest, listenerId: string): bool =
    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        conquestDb.exec("DELETE FROM listeners WHERE listenerId = ?", listenerId)

        conquestDb.close()
    except: 
        return false
    
    return true

proc dbListenerExists*(cq: Conquest, listenerName: string): bool =
    try:
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        let res = conquestDb.one("SELECT 1 FROM listeners WHERE listenerId = ? LIMIT 1", listenerName)
        
        conquestDb.close()

        return res.isSome
    except:
        cq.error(getCurrentExceptionMsg())
        return false