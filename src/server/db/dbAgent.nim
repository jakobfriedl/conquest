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
        INSERT INTO agents (agentId, listenerId, process, pid, username, impersonationToken, hostname, domain, ipInternal, ipExternal, os, elevated, sleep, jitter, modules, firstCheckin, latestCheckin, sessionKey)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, agent.agentId, agent.listenerId, agent.process, agent.pid, agent.username, agent.impersonationToken, agent.hostname, agent.domain, agent.ipInternal, agent.ipExternal, agent.os, agent.elevated, agent.sleep, agent.jitter, agent.modules, agent.firstCheckin, agent.latestCheckin, sessionKeyBlob)

        conquestDb.close() 
    except: 
        cq.error(getCurrentExceptionMsg())
        return false
    
    return true

proc dbGetAllAgents*(cq: Conquest): seq[Agent] = 
    var agents: seq[Agent] = @[]

    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        for row in conquestDb.iterate("SELECT agentId, listenerId, sleep, jitter, process, pid, username, impersonationToken, hostname, domain, ipInternal, ipExternal, os, elevated, modules, firstCheckin, latestCheckin, sessionKey FROM agents;"):
            let (agentId, listenerId, sleep, jitter, process, pid, username, impersonationToken, hostname, domain, ipInternal, ipExternal, os, elevated, modules, firstCheckin, latestCheckin, sessionKeyBlob) = row.unpack((string, string, int, int, string, int, string, string, string, string, string, string, string, bool, uint32, int64, int64, seq[byte]))

            # Convert session key blob back to array
            var sessionKey: Key
            if sessionKeyBlob.len == 32:
                copyMem(addr sessionKey[0], addr sessionKeyBlob[0], 32)
            else:
                # Handle invalid session key - log error but continue
                cq.warning("Invalid session key length for agent: ", agentId)

            let a = Agent(
                agentId: agentId,
                listenerId: listenerId,
                sleep: sleep,
                jitter: jitter,
                pid: pid,
                username: username,
                impersonationToken: impersonationToken,
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

proc dbDeleteAgentByName*(cq: Conquest, agentId: string): bool =
    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        conquestDb.exec("DELETE FROM agents WHERE agentId = ?", agentId)

        conquestDb.close()
    except: 
        cq.error(getCurrentExceptionMsg())
        return false
    
    return true

proc dbAgentExists*(cq: Conquest, agentId: string): bool =
    try:
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        let res = conquestDb.one("SELECT 1 FROM agents WHERE agentId = ? LIMIT 1", agentId)
        
        conquestDb.close()

        return res.isSome
    except:
        cq.error(getCurrentExceptionMsg())
        return false

proc dbUpdateTokenImpersonation*(cq: Conquest, agentId: string, impersonationToken: string): bool =
    try:
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        conquestDb.exec("UPDATE agents SET impersonationToken = ? WHERE agentId = ?", impersonationToken, agentId)

        conquestDb.close()
        return true
    except:
        cq.error(getCurrentExceptionMsg())
        return false