import system, tables, terminal, tiny_sqlite, sequtils
import ../core/logger
import ../../types/[common, server, protocol]
import ./dbLink

#[
    Agent database functions
]#

proc dbStoreAgent*(cq: Conquest, agent: Agent): bool = 
    try: 
        let sessionKeyBlob = agent.sessionKey.toSeq()
        cq.db.exec("""
        INSERT INTO agents (agentId, listenerId, process, pid, username, impersonationToken, hostname, domain, ipInternal, ipExternal, os, elevated, sleep, jitter, modules, firstCheckin, latestCheckin, sessionKey)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, agent.agentId, agent.listenerId, agent.process, agent.pid, agent.username, agent.impersonationToken, agent.hostname, agent.domain, agent.ipInternal, agent.ipExternal, agent.os, agent.elevated, agent.sleep, agent.jitter, agent.modules, agent.firstCheckin, agent.latestCheckin, sessionKeyBlob)
    except: 
        cq.error(getCurrentExceptionMsg())
        return false
    return true

proc dbGetAllAgents*(cq: Conquest) = 
    try: 
        let rows = cq.db.all("SELECT agentId, listenerId, sleep, jitter, process, pid, username, impersonationToken, hostname, domain, ipInternal, ipExternal, os, elevated, modules, firstCheckin, latestCheckin, sessionKey FROM agents;")
        for row in rows:
            let (agentId, listenerId, sleep, jitter, process, pid, username, impersonationToken, hostname, domain, ipInternal, ipExternal, os, elevated, modules, firstCheckin, latestCheckin, sessionKeyBlob) = row.unpack((string, string, int, int, string, int, string, string, string, string, string, string, string, bool, uint32, int64, int64, seq[byte]))
            
            var sessionKey: Key
            if sessionKeyBlob.len == 32:
                copyMem(addr sessionKey[0], addr sessionKeyBlob[0], 32)
            else:
                cq.warning("Invalid session key length for agent: ", agentId)
            
            cq.agents[agentId] = Agent(
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
                latestCheckin: cast[int64](latestCheckin),
                process: process,
                modules: cast[uint32](modules),
                sessionKey: sessionKey,
                tasks: @[],
                taskCommands: initTable[Uuid, string](),
                links: cq.dbGetLinkedAgents(agentId)
            )
    except: 
        cq.error(getCurrentExceptionMsg())

proc dbDeleteAgentById*(cq: Conquest, agentId: string) =
    try: 
        cq.db.exec("DELETE FROM agents WHERE agentId = ?", agentId)
        cq.agents.del(agentId)
    except: 
        cq.error(getCurrentExceptionMsg())

proc dbAgentExists*(cq: Conquest, agentId: string): bool =
    let res = cq.db.one("SELECT 1 FROM agents WHERE agentId = ? LIMIT 1", agentId)
    return res.isSome

proc dbUpdateTokenImpersonation*(cq: Conquest, agentId: string, impersonationToken: string): bool =
    try:
        cq.db.exec("UPDATE agents SET impersonationToken = ? WHERE agentId = ?", impersonationToken, agentId)
        return true
    except:
        cq.error(getCurrentExceptionMsg())
        return false