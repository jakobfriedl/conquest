import strformat, strutils, system, terminal, tiny_sqlite
import std/options
import ../core/logger
import ../../types/[common, server]

#[
    Listener database functions
]#
proc dbStoreListener*(cq: Conquest, listener: Listener): bool = 
    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)
        
        case listener.listenerType:
        of LISTENER_HTTP:
            conquestDb.exec("""
                INSERT INTO listeners (listenerId, listenerType, hosts, address, port, pipe)
                VALUES (?, ?, ?, ?, ?, NULL);
            """, listener.listenerId, $listener.listenerType, 
                 listener.hosts, listener.address, listener.port)
        
        of LISTENER_SMB:
            conquestDb.exec("""
                INSERT INTO listeners (listenerId, listenerType, hosts, address, port, pipe)
                VALUES (?, ?, NULL, NULL, NULL, ?);
            """, listener.listenerId, $listener.listenerType, listener.pipe)
        
        conquestDb.close() 
        return true
    except: 
        cq.error(getCurrentExceptionMsg())
        return false

proc dbGetAllListeners*(cq: Conquest): seq[UIListener] = 
    var listeners: seq[UIListener] = @[]
    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)
        
        for row in conquestDb.iterate("SELECT listenerId, listenerType, hosts, address, port, pipe FROM listeners;"):
            let (listenerId, listenerType, hosts, address, port, pipe) = row.unpack((string, string, Option[string], Option[string], Option[int], Option[string]))
            
            case parseEnum[ListenerType](listenerType):
            of LISTENER_HTTP:
                listeners.add(UIListener(
                    listenerId: listenerId,
                    listenerType: LISTENER_HTTP,
                    hosts: hosts.get(""),
                    address: address.get(""),
                    port: port.get(0)
                ))
            of LISTENER_SMB:
                listeners.add(UIListener(
                    listenerId: listenerId,
                    listenerType: LISTENER_SMB,
                    pipe: pipe.get("")
                ))
        
        conquestDb.close()
    except: 
        cq.error(getCurrentExceptionMsg())
    
    return listeners

proc dbDeleteListenerByName*(cq: Conquest, listenerId: string): bool =
    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)
        conquestDb.exec("DELETE FROM listeners WHERE listenerId = ?", listenerId)
        conquestDb.close()
        return true
    except: 
        cq.error(getCurrentExceptionMsg())
        return false

proc dbListenerExists*(cq: Conquest, listenerId: string): bool =
    try:
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)
        let res = conquestDb.one("SELECT 1 FROM listeners WHERE listenerId = ? LIMIT 1", listenerId)
        conquestDb.close()
        return res.isSome
    except:
        cq.error(getCurrentExceptionMsg())
        return false