import strformat, strutils, system, terminal, tiny_sqlite
import std/options
import ../core/logger
import ../../types/[common, server]

#[
    Listener database functions
]#

proc dbStoreListener*(cq: Conquest, listener: Listener): bool = 
    try: 
        case listener.listenerType:
        of LISTENER_HTTP:
            cq.db.exec("""
                INSERT INTO listeners (listenerId, listenerType, name, timestamp, address, port, hosts, profile, pipe)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL);
            """, listener.listenerId, $listener.listenerType, listener.name, listener.timestamp, listener.address, listener.port, listener.hosts, listener.profile)
        of LISTENER_SMB:
            cq.db.exec("""
                INSERT INTO listeners (listenerId, listenerType, name, timestamp, address, port, hosts, profile, pipe)
                VALUES (?, ?, ?, ?, NULL, NULL, NULL, NULL, ?);
            """, listener.listenerId, $listener.listenerType, listener.name, listener.timestamp, listener.pipe)
        return true
    except: 
        cq.error(getCurrentExceptionMsg())
        return false

proc dbGetAllListeners*(cq: Conquest): seq[UIListener] = 
    try:
        let rows = cq.db.all("SELECT listenerId, listenerType, name, timestamp, address, port, hosts, profile, pipe FROM listeners;")
        for row in rows:
            let (listenerId, listenerType, name, timestamp, address, port, hosts, profile, pipe) = row.unpack((string, string, string, int64, Option[string], Option[int], Option[string], Option[string], Option[string]))
            case parseEnum[ListenerType](listenerType):
            of LISTENER_HTTP:
                result.add(UIListener(
                    listenerId: listenerId,
                    listenerType: LISTENER_HTTP,
                    name: name,
                    timestamp: timestamp,
                    hosts: hosts.get(""),
                    address: address.get(""),
                    port: port.get(0),
                    profile: profile.get("")
                ))
            of LISTENER_SMB:
                result.add(UIListener(
                    listenerId: listenerId,
                    listenerType: LISTENER_SMB,
                    name: name,
                    timestamp: timestamp,
                    pipe: pipe.get("")
                ))
    except: 
        cq.error(getCurrentExceptionMsg())

proc dbDeleteListenerByName*(cq: Conquest, listenerId: string): bool =
    try: 
        cq.db.exec("DELETE FROM listeners WHERE listenerId = ?", listenerId)
        return true
    except: 
        cq.error(getCurrentExceptionMsg())
        return false

proc dbListenerExists*(cq: Conquest, listenerId: string): bool =
    let res = cq.db.one("SELECT 1 FROM listeners WHERE listenerId = ? LIMIT 1", listenerId)
    return res.isSome