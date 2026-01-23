import system, terminal, tiny_sqlite
import ../core/logger
import ../../common/[types, utils]

proc dbStoreLink*(cq: Conquest, parent, child: string): bool = 
    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        conquestDb.exec("""
        INSERT INTO links (linkId, parentId, childId)
        VALUES (?, ?, ?);
        """, generateUuid(), parent, child)

        conquestDb.close() 
    except: 
        cq.error(getCurrentExceptionMsg())
        return false
    
    return true

proc dbGetLinkedAgents*(cq: Conquest, agentId: string): seq[string] = 
    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        for row in conquestDb.iterate("SELECT linkId, parentId, childId FROM links WHERE parentId = ?;", agentId):
            let (_, _, childId) = row.unpack((string, string, string))
            result.add(childId)

        conquestDb.close()
    except: 
        cq.error(getCurrentExceptionMsg())

proc dbDeleteLink*(cq: Conquest, parent, child: string): bool = 
    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        conquestDb.exec("DELETE FROM links WHERE parentId = ? AND childId = ?", parent, child)

        conquestDb.close()
    except: 
        return false
    
    return true