import tiny_sqlite, net
import ../types

import system, terminal, strformat

proc dbInit*(cq: Conquest) =

    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        # Create tables
        conquestDb.execScript("""
        CREATE TABLE listeners (
            name TEXT PRIMARY KEY,
            address TEXT NOT NULL,
            port INTEGER NOT NULL UNIQUE,
            protocol TEXT NOT NULL CHECK (protocol IN ('http')),
            sleep INTEGER NOT NULL,
            jitter REAL NOT NULL
        );

        CREATE TABLE agents (
            name TEXT PRIMARY KEY,                   
            listener TEXT NOT NULL,                    
            pid INTEGER NOT NULL,
            username TEXT NOT NULL,
            hostname TEXT NOT NULL,
            ip TEXT NOT NULL,
            os TEXT NOT NULL,
            elevated BOOLEAN NOT NULL,
            sleep INTEGER DEFAULT 10,
            jitter REAL DEFAULT 0.1,
            FOREIGN KEY (listener) REFERENCES listeners(name)
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
        INSERT INTO listeners (name, address, port, protocol, sleep, jitter)
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

        for row in conquestDb.iterate("SELECT name, address, port, protocol, sleep, jitter FROM listeners;"):
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

        conquestDb.exec("DELETE FROM listeners WHERE name = ?", name)

        conquestDb.close()
    except: 
        return false
    
    return true

proc listenerExists*(cq: Conquest, listenerName: string): bool =
    try:
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        let res = conquestDb.one("SELECT 1 FROM listeners WHERE name = ? LIMIT 1", listenerName)
        
        conquestDb.close()

        return res.isSome
    except:
        cq.writeLine(fgRed, styleBright, "[-] ", getCurrentExceptionMsg())
        return false

proc dbStoreAgent*(cq: Conquest, agent: Agent): bool = 
    
    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        conquestDb.exec("""
        INSERT INTO agents (name, listener, sleep, jitter, pid,username, hostname, ip, os, elevated)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, agent.name, agent.listener, agent.sleep, agent.jitter, agent.pid, agent.username, agent.hostname, agent.ip, agent.os, agent.elevated)

        conquestDb.close() 
    except: 
        cq.writeLine(fgRed, styleBright, "[-] ", getCurrentExceptionMsg())
        return false
    
    return true

