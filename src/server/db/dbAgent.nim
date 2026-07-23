import system, tables, terminal, tiny_sqlite, sequtils, locks
import ../core/logger
import ../../types/[common, server]

#[
    Agent database functions
]#

proc dbStoreAgent*(cq: Conquest, agent: Agent): bool =
    withLock(cq.dbLock):
        try:
            let sessionKeyBlob = agent.sessionKey.toSeq()
            cq.db.exec("""
            INSERT INTO agents (agentId, listenerId, process, pid, arch, username, impersonationToken, hostname, domain, ipInternal, ipExternal, os, elevated, sleep, modules, firstCheckin, latestCheckin, sessionKey)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """, agent.agentId, agent.listenerId, agent.process, agent.pid, agent.arch, agent.username, agent.impersonationToken, agent.hostname, agent.domain, agent.ipInternal, agent.ipExternal, agent.os, agent.elevated, agent.sleep, agent.modules, agent.firstCheckin, agent.latestCheckin, sessionKeyBlob)
        except:
            cq.error(getCurrentExceptionMsg())
            return false
    return true

proc dbGetAllAgents*(cq: Conquest) =
    withLock(cq.dbLock):
        try:
            let agentRows = cq.db.all("SELECT agentId, listenerId, sleep, process, pid, arch, username, impersonationToken, hostname, domain, ipInternal, ipExternal, os, elevated, modules, firstCheckin, latestCheckin, sessionKey FROM agents;")
            let linkRows = cq.db.all("SELECT parentId, childId FROM links;")

            var linksByParent = initTable[string, seq[string]]()
            for row in linkRows:
                let (parentId, childId) = row.unpack((string, string))
                linksByParent.mgetOrPut(parentId, @[]).add(childId)

            for row in agentRows:
                let (agentId, listenerId, sleep, process, pid, arch, username, impersonationToken, hostname, domain, ipInternal, ipExternal, os, elevated, modules, firstCheckin, latestCheckin, sessionKeyBlob) = row.unpack((string, string, int, string, int, string, string, string, string, string, string, string, string, bool, uint32, int64, int64, seq[byte]))

                var sessionKey: Key
                if sessionKeyBlob.len == 32:
                    copyMem(addr sessionKey[0], addr sessionKeyBlob[0], 32)
                else:
                    cq.warning("Invalid session key length for agent: ", agentId)

                cq.agents[agentId] = Agent(
                    agentId: agentId,
                    listenerId: listenerId,
                    sleep: sleep,
                    process: process,
                    pid: pid,
                    arch: arch,
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
                    modules: cast[uint32](modules),
                    sessionKey: sessionKey,
                    tasks: @[],
                    taskCommands: initTable[Uuid, string](),
                    links: linksByParent.getOrDefault(agentId, @[])
                )
        except:
            cq.error(getCurrentExceptionMsg())

proc dbDeleteAgentById*(cq: Conquest, agentId: string) =
    withLock(cq.dbLock):
        try:
            cq.db.exec("DELETE FROM agents WHERE agentId = ?", agentId)
            cq.agents.del(agentId)
        except:
            cq.error(getCurrentExceptionMsg())

proc dbAgentExists*(cq: Conquest, agentId: string): bool =
    withLock(cq.dbLock):
        try:
            let res = cq.db.one("SELECT 1 FROM agents WHERE agentId = ? LIMIT 1", agentId)
            return res.isSome
        except:
            cq.error(getCurrentExceptionMsg())
            return false

proc dbUpdateAgent*(cq: Conquest, agent: Agent): bool =
    withLock(cq.dbLock):
        try:
            let sessionKeyBlob = agent.sessionKey.toSeq()
            cq.db.exec("""
            UPDATE agents SET listenerId = ?, process = ?, pid = ?, arch = ?, username = ?, impersonationToken = ?, hostname = ?, domain = ?, ipInternal = ?, ipExternal = ?, os = ?, elevated = ?, sleep = ?, modules = ?, latestCheckin = ?, sessionKey = ?
            WHERE agentId = ?;""", agent.listenerId, agent.process, agent.pid, agent.arch, agent.username, agent.impersonationToken, agent.hostname, agent.domain, agent.ipInternal, agent.ipExternal, agent.os, agent.elevated, agent.sleep, agent.modules, agent.latestCheckin, sessionKeyBlob, agent.agentId)
            cq.agents[agent.agentId] = agent
            return true
        except:
            cq.error(getCurrentExceptionMsg())
            return false
