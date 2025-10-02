import system, terminal, tiny_sqlite, sequtils

import ../core/logger
import ../../common/types

#[
    Agent database functions - Updated with session key support (no jitter)
]#

proc dbStoreAgent*(cq: Conquest, agent: Agent): bool = 
    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        # Convert session key to blob for storage
        let sessionKeyBlob = agent.sessionKey.toSeq()

        conquestDb.exec("""
        INSERT INTO agents (name, listener, process, pid, username, hostname, domain, ipInternal, ipExternal, os, elevated, sleep, modules, firstCheckin, latestCheckin, sessionKey)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, agent.agentId, agent.listenerId, agent.process, agent.pid, agent.username, agent.hostname, agent.domain, agent.ipInternal, agent.ipExternal, agent.os, agent.elevated, agent.sleep, agent.modules, agent.firstCheckin, agent.latestCheckin, sessionKeyBlob)

        conquestDb.close() 
    except: 
        cq.error(getCurrentExceptionMsg())
        return false
    
    return true

proc dbGetAllAgents*(cq: Conquest): seq[Agent] = 
    var agents: seq[Agent] = @[]

    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        for row in conquestDb.iterate("SELECT name, listener, sleep, process, pid, username, hostname, domain, ipInternal, ipExternal, os, elevated, modules, firstCheckin, latestCheckin, sessionKey FROM agents;"):
            let (agentId, listenerId, sleep, process, pid, username, hostname, domain, ipInternal, ipExternal, os, elevated, modules, firstCheckin, latestCheckin, sessionKeyBlob) = row.unpack((string, string, int, string, int, string, string, string, string, string, string, bool, uint32, int64, int64, seq[byte]))

            # Convert session key blob back to array
            var sessionKey: Key
            if sessionKeyBlob.len == 32:
                copyMem(sessionKey[0].addr, sessionKeyBlob[0].unsafeAddr, 32)
            else:
                # Handle invalid session key - log error but continue
                cq.warning("Invalid session key length for agent: ", agentId)

            let a = Agent(
                agentId: agentId,
                listenerId: listenerId,
                sleep: sleep,
                pid: pid,
                username: username,
                hostname: hostname,
                domain: domain,
                ipInternal: ipInternal, 
                ipExternal: ipExternal,
                os: os,
                elevated: elevated,
                firstCheckin: cast[int64](firstCheckin),
                latestCheckin: cast[int64](firstCheckin),
                process: process,
                modules: cast[uint32](modules),
                sessionKey: sessionKey,
                tasks: @[]  # Initialize empty tasks
            )

            agents.add(a)

        conquestDb.close()
    except: 
        cq.error(getCurrentExceptionMsg())

    return agents

proc dbGetAllAgentsByListener*(cq: Conquest, listenerName: string): seq[Agent] = 
    var agents: seq[Agent] = @[]

    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        for row in conquestDb.iterate("SELECT name, listener, sleep, process, pid, username, hostname, domain, ipInternal, ipExternal, os, elevated, modules, firstCheckin, latestCheckin, sessionKey FROM agents WHERE listener = ?;", listenerName):
            let (agentId, listenerId, sleep, process, pid, username, hostname, domain, ipInternal, ipExternal, os, elevated, modules, firstCheckin, latestCheckin, sessionKeyBlob) = row.unpack((string, string, int, string, int, string, string, string, string, string, string, bool, uint32, int64, int64, seq[byte]))

            # Convert session key blob back to array
            var sessionKey: Key
            if sessionKeyBlob.len == 32:
                copyMem(sessionKey[0].addr, sessionKeyBlob[0].unsafeAddr, 32)
            else:
                # Handle invalid session key - log error but continue
                cq.warning("Invalid session key length for agent: ", agentId)

            let a = Agent(
                agentId: agentId,
                listenerId: listenerId,
                sleep: sleep,
                pid: pid,
                username: username,
                hostname: hostname,
                domain: domain,
                ipInternal: ipInternal, 
                ipExternal: ipExternal,
                os: os,
                elevated: elevated,
                firstCheckin: cast[int64](firstCheckin),
                latestCheckin: cast[int64](firstCheckin),
                process: process,
                modules: cast[uint32](modules),
                sessionKey: sessionKey,
                tasks: @[]  # Initialize empty tasks
            )

        conquestDb.close()
    except: 
        cq.error(getCurrentExceptionMsg())

    return agents

proc dbDeleteAgentByName*(cq: Conquest, name: string): bool =
    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        conquestDb.exec("DELETE FROM agents WHERE name = ?", name)

        conquestDb.close()
    except: 
        cq.error(getCurrentExceptionMsg())
        return false
    
    return true

proc dbAgentExists*(cq: Conquest, agentName: string): bool =
    try:
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        let res = conquestDb.one("SELECT 1 FROM agents WHERE name = ? LIMIT 1", agentName)
        
        conquestDb.close()

        return res.isSome
    except:
        cq.error(getCurrentExceptionMsg())
        return false

proc dbUpdateSleep*(cq: Conquest, agentName: string, delay: int): bool =
    try:
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        conquestDb.exec("UPDATE agents SET sleep = ? WHERE name = ?", delay, agentName)

        conquestDb.close()
        return true
    except:
        cq.error(getCurrentExceptionMsg())
        return false