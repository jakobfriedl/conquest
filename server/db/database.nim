import tiny_sqlite, net
import ../types

import system, terminal, strformat

proc dbInit*(console: Console) =

    try: 
        let conquestDb = openDatabase(console.dbPath, mode=dbReadWrite)

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
        
        console.writeLine(fgGreen, "[+] ", console.dbPath, ": Database created.")
        conquestDb.close()
    except SqliteError: 
        console.writeLine(fgGreen, "[+] ", console.dbPath, ": Database file found.")

proc dbStore*(console: Console, listener: Listener): bool = 

    try: 
        let conquestDb = openDatabase(console.dbPath, mode=dbReadWrite)

        conquestDb.exec("""
        INSERT INTO listener (name, address, port, protocol, sleep, jitter)
        VALUES (?, ?, ?, ?, ?, ?);
        """, listener.name, listener.address, listener.port, $listener.protocol, listener.sleep, listener.jitter)

        conquestDb.close() 
    except: 
        console.writeLine(fgRed, styleBright, "[-] ", getCurrentExceptionMsg())
        return false
    
    return true

proc dbGetAllListeners*(console: Console): seq[Listener] = 

    var listeners: seq[Listener] = @[]

    try: 
        let conquestDb = openDatabase(console.dbPath, mode=dbReadWrite)

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
        console.writeLine(fgRed, styleBright, "[-] ", getCurrentExceptionMsg())

    return listeners

proc dbDeleteListenerByName*(console: Console, name: string): bool =
    try: 
        let conquestDb = openDatabase(console.dbPath, mode=dbReadWrite)

        conquestDb.exec("DELETE FROM listener WHERE name = ?", name)

        conquestDb.close()
    except: 
        return false
    
    return true

proc dbStore*(agent: Agent): bool = 
    discard