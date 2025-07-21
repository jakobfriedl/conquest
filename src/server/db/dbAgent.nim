import system, terminal, tiny_sqlite, times

import ../utils
import ../../common/[types, utils]

#[
    Agent database functions
]#
proc dbStoreAgent*(cq: Conquest, agent: Agent): bool = 
    
    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        conquestDb.exec("""
        INSERT INTO agents (name, listener, process, pid, username, hostname, domain, ip, os, elevated, sleep, jitter, firstCheckin, latestCheckin)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, agent.agentId, agent.listenerId, agent.process, agent.pid, agent.username, agent.hostname, agent.domain, agent.ip, agent.os, agent.elevated, agent.sleep, agent.jitter, agent.firstCheckin.format("dd-MM-yyyy HH:mm:ss"), agent.latestCheckin.format("dd-MM-yyyy HH:mm:ss"))

        conquestDb.close() 
    except: 
        cq.writeLine(fgRed, styleBright, "[-] ", getCurrentExceptionMsg())
        return false
    
    return true

proc dbGetAllAgents*(cq: Conquest): seq[Agent] = 

    var agents: seq[Agent] = @[]

    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        for row in conquestDb.iterate("SELECT name, listener, sleep, jitter, process, pid, username, hostname, domain, ip, os, elevated, firstCheckin, latestCheckin FROM agents;"):
            let (agentId, listenerId, sleep, jitter, process, pid, username, hostname, domain, ip, os, elevated, firstCheckin, latestCheckin) = row.unpack((string, string, int, float, string, int, string, string, string, string, string, bool, string, string))

            let a = Agent(
                    agentId: agentId,
                    listenerId: listenerId,
                    sleep: sleep,
                    pid: pid,
                    username: username,
                    hostname: hostname,
                    domain: domain,
                    ip: ip,
                    os: os,
                    elevated: elevated,
                    firstCheckin: parse(firstCheckin, "dd-MM-yyyy HH:mm:ss"),
                    latestCheckin: parse(latestCheckin, "dd-MM-yyyy HH:mm:ss"),
                    jitter: jitter,
                    process: process 
                )

            agents.add(a)

        conquestDb.close()
    except: 
        cq.writeLine(fgRed, styleBright, "[-] ", getCurrentExceptionMsg())

    return agents

proc dbGetAllAgentsByListener*(cq: Conquest, listenerName: string): seq[Agent] = 

    var agents: seq[Agent] = @[]

    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        for row in conquestDb.iterate("SELECT name, listener, sleep, jitter, process, pid, username, hostname, domain, ip, os, elevated, firstCheckin, latestCheckin FROM agents WHERE listener = ?;", listenerName):
            let (agentId, listenerId, sleep, jitter, process, pid, username, hostname, domain, ip, os, elevated, firstCheckin, latestCheckin) = row.unpack((string, string, int, float, string, int, string, string, string, string, string, bool, string, string))

            let a = Agent(
                    agentId: agentId,
                    listenerId: listenerId,
                    sleep: sleep,
                    pid: pid,
                    username: username,
                    hostname: hostname,
                    domain: domain,
                    ip: ip,
                    os: os,
                    elevated: elevated,
                    firstCheckin: parse(firstCheckin, "dd-MM-yyyy HH:mm:ss"),
                    latestCheckin: parse(latestCheckin, "dd-MM-yyyy HH:mm:ss"),
                    jitter: jitter,
                    process: process,
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

proc dbUpdateCheckin*(cq: Conquest, agentName: string, timestamp: string): bool =
    try:
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        conquestDb.exec("UPDATE agents SET latestCheckin = ? WHERE name = ?", timestamp, agentName)

        conquestDb.close()
        return true
    except:
        cq.writeLine(fgRed, styleBright, "[-] ", getCurrentExceptionMsg())
        return false

proc dbUpdateSleep*(cq: Conquest, agentName: string, delay: int): bool =
    try:
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        conquestDb.exec("UPDATE agents SET sleep = ? WHERE name = ?", delay, agentName)

        conquestDb.close()
        return true
    except:
        cq.writeLine(fgRed, styleBright, "[-] ", getCurrentExceptionMsg())
        return false