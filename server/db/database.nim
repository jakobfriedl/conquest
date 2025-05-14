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
            protocol TEXT NOT NULL CHECK (protocol IN ('http'))
        );

        CREATE TABLE agents (
            name TEXT PRIMARY KEY,                   
            listener TEXT NOT NULL, 
            process TEXT NOT NULL,                   
            pid INTEGER NOT NULL,
            username TEXT NOT NULL,
            hostname TEXT NOT NULL,
            domain TEXT NOT NULL,
            ip TEXT NOT NULL,
            os TEXT NOT NULL,
            elevated BOOLEAN NOT NULL,
            sleep INTEGER DEFAULT 10,
            jitter REAL DEFAULT 0.1,
            firstCheckin DATETIME NOT NULL,
            FOREIGN KEY (listener) REFERENCES listeners(name)
        );

        """)
        
        cq.writeLine(fgGreen, "[+] ", cq.dbPath, ": Database created.")
        conquestDb.close()
    except SqliteError: 
        cq.writeLine(fgGreen, "[+] ", cq.dbPath, ": Database file found.")

#[
    Listener database functions
]#
proc dbStoreListener*(cq: Conquest, listener: Listener): bool = 

    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        conquestDb.exec("""
        INSERT INTO listeners (name, address, port, protocol)
        VALUES (?, ?, ?, ?);
        """, listener.name, listener.address, listener.port, $listener.protocol)

        conquestDb.close() 
    except: 
        cq.writeLine(fgRed, styleBright, "[-] ", getCurrentExceptionMsg())
        return false
    
    return true

proc dbGetAllListeners*(cq: Conquest): seq[Listener] = 

    var listeners: seq[Listener] = @[]

    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        for row in conquestDb.iterate("SELECT name, address, port, protocol FROM listeners;"):
            let (name, address, port, protocol) = row.unpack((string, string, int, string))
            
            let l = Listener(
                name: name,
                address: address,
                port: port,
                protocol: stringToProtocol(protocol),
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

proc dbListenerExists*(cq: Conquest, listenerName: string): bool =
    try:
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        let res = conquestDb.one("SELECT 1 FROM listeners WHERE name = ? LIMIT 1", listenerName)
        
        conquestDb.close()

        return res.isSome
    except:
        cq.writeLine(fgRed, styleBright, "[-] ", getCurrentExceptionMsg())
        return false

#[
    Agent database functions
]#
proc dbStoreAgent*(cq: Conquest, agent: Agent): bool = 
    
    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        conquestDb.exec("""
        INSERT INTO agents (name, listener, process, pid, username, hostname, domain, ip, os, elevated, sleep, jitter, firstCheckin)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, agent.name, agent.listener, agent.process, agent.pid, agent.username, agent.hostname, agent.domain, agent.ip, agent.os, agent.elevated, agent.sleep, agent.jitter, $agent.firstCheckin)

        conquestDb.close() 
    except: 
        cq.writeLine(fgRed, styleBright, "[-] ", getCurrentExceptionMsg())
        return false
    
    return true

proc dbGetAllAgents*(cq: Conquest): seq[Agent] = 

    var agents: seq[Agent] = @[]

    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        for row in conquestDb.iterate("SELECT name, listener, sleep, jitter, process, pid, username, hostname, domain, ip, os, elevated, firstCheckin FROM agents;"):
            let (name, listener, sleep, jitter, process, pid, username, hostname, domain, ip, os, elevated, firstCheckin) = row.unpack((string, string, int, float, string, int, string, string, string, string, string, bool, string))

            let a = Agent(
                    name: name,
                    listener: listener,
                    sleep: sleep,
                    pid: pid,
                    username: username,
                    hostname: hostname,
                    domain: domain,
                    ip: ip,
                    os: os,
                    elevated: elevated,
                    firstCheckin: firstCheckin,
                    jitter: jitter,
                    process: process,
                    tasks: @[] 
                )

            agents.add(a)

        conquestDb.close()
    except: 
        cq.writeLine(fgRed, styleBright, "[-] ", getCurrentExceptionMsg())

    return agents

proc dbDeleteAgentByName*(cq: Conquest, name: string): bool =
    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        conquestDb.exec("DELETE FROM agents WHERE name = ?", name)

        conquestDb.close()
    except: 
        return false
    
    return true

proc dbAgentExists*(cq: Conquest, agentName: string): bool =
    try:
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        let res = conquestDb.one("SELECT 1 FROM agents WHERE name = ? LIMIT 1", agentName)
        
        conquestDb.close()

        return res.isSome
    except:
        cq.writeLine(fgRed, styleBright, "[-] ", getCurrentExceptionMsg())
        return false