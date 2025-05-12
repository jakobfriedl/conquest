import tiny_sqlite, net
import ../types

import system, terminal, strformat

proc dbInit*(cq: Conquest) =

    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        # Create tables
        conquestDb.execScript("""
        CREATE TABLE listener (
            name TEXT PRIMARY KEY,
            address TEXT NOT NULL,
            port INTEGER NOT NULL UNIQUE,
            protocol TEXT NOT NULL CHECK (protocol IN ('http')),
            sleep INTEGER NOT NULL,
            jitter REAL NOT NULL
        );

        """)
        
        cq.writeLine(fgGreen, "[+] ", cq.dbPath, ": Database created.")
        conquestDb.close()
    except SqliteError: 
        cq.writeLine(fgGreen, "[+] ", cq.dbPath, ": Database file found.")

proc dbStoreListener*(cq: Conquest, listener: Listener): bool = 

    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        conquestDb.exec("""
        INSERT INTO listener (name, address, port, protocol, sleep, jitter)
        VALUES (?, ?, ?, ?, ?, ?);
        """, listener.name, listener.address, listener.port, $listener.protocol, listener.sleep, listener.jitter)

        conquestDb.close() 
    except: 
        cq.writeLine(fgRed, styleBright, "[-] ", getCurrentExceptionMsg())
        return false
    
    return true

proc dbGetAllListeners*(cq: Conquest): seq[Listener] = 

    var listeners: seq[Listener] = @[]

    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        for row in conquestDb.iterate("SELECT name, address, port, protocol, sleep, jitter FROM listener;"):
            let (name, address, port, protocol, sleep, jitter) = row.unpack((string, string, int, string, int, float ))
            
            let l = Listener(
                name: name,
                address: address,
                port: port,
                protocol: stringToProtocol(protocol),
                sleep: sleep,
                jitter: jitter
            )
            listeners.add(l)

        conquestDb.close()
    except: 
        cq.writeLine(fgRed, styleBright, "[-] ", getCurrentExceptionMsg())

    return listeners

proc dbDeleteListenerByName*(cq: Conquest, name: string): bool =
    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        conquestDb.exec("DELETE FROM listener WHERE name = ?", name)

        conquestDb.close()
    except: 
        return false
    
    return true

proc dbStoreAgent*(agent: Agent): bool = 
    discard