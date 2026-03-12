import system, terminal, tiny_sqlite
import ../core/logger
import ../../common/utils
import ../../types/server

#[
    Link database functions
]#

proc dbStoreLink*(cq: Conquest, parent, child: string): bool = 
    try: 
        cq.db.exec("""
        INSERT INTO links (linkId, parentId, childId)
        VALUES (?, ?, ?);
        """, generateUuid(), parent, child)
    except: 
        cq.error(getCurrentExceptionMsg())
        return false
    return true

proc dbGetLinkedAgents*(cq: Conquest, agentId: string): seq[string] = 
    try:
        let rows = cq.db.all("SELECT linkId, parentId, childId FROM links WHERE parentId = ?;", agentId)
        for row in rows:
            let (_, _, childId) = row.unpack((string, string, string))
            result.add(childId)
    except: 
        cq.error(getCurrentExceptionMsg())

proc dbDeleteLink*(cq: Conquest, parent, child: string): bool = 
    try: 
        cq.db.exec("DELETE FROM links WHERE parentId = ? AND childId = ?", parent, child)
    except: 
        cq.error(getCurrentExceptionMsg())
        return false
    return true