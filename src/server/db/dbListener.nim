import system, terminal, tiny_sqlite

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
        INSERT INTO listeners (name, address, port, protocol)
        VALUES (?, ?, ?, ?);
        """, listener.listenerId, listener.address, listener.port, $listener.protocol)

        conquestDb.close() 
    except: 
        cq.error(getCurrentExceptionMsg())
        return false
    
    return true

proc dbGetAllListeners*(cq: Conquest): seq[Listener] = 

    var listeners: seq[Listener] = @[]

    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        for row in conquestDb.iterate("SELECT name, address, port, protocol FROM listeners;"):
            let (listenerId, address, port, protocol) = row.unpack((string, string, int, string))
            
            let l = Listener(
                listenerId: listenerId,
                address: address,
                port: port,
                protocol: stringToProtocol(protocol),
            )
            listeners.add(l)

        conquestDb.close()
    except: 
        cq.error(getCurrentExceptionMsg())

    return listeners

proc dbDeleteListenerByName*(cq: Conquest, name: string): bool =
    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        conquestDb.exec("DELETE FROM listeners WHERE name = ?", name)

        conquestDb.close()
    except: 
        return false
    
    return true

proc dbListenerExists*(cq: Conquest, listenerName: string): bool =
    try:
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        let res = conquestDb.one("SELECT 1 FROM listeners WHERE name = ? LIMIT 1", listenerName)
        
        conquestDb.close()

        return res.isSome
    except:
        cq.error(getCurrentExceptionMsg())
        return false