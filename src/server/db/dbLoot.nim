import system, terminal, tiny_sqlite
import ../core/logger
import ../../common/types

proc dbStoreLoot*(cq: Conquest, loot: LootItem): bool = 
    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        conquestDb.exec("""
        INSERT INTO loot (lootId, itemType, agentId, host, path, timestamp, size)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """, loot.lootId, int(loot.itemType), loot.agentId, loot.host, loot.path, loot.timestamp, loot.size)

        conquestDb.close() 
    except: 
        cq.error(getCurrentExceptionMsg())
        return false
    
    return true

proc dbGetLoot*(cq: Conquest): seq[LootItem] = 
    var loot: seq[LootItem] = @[]

    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        for row in conquestDb.iterate("SELECT lootId, itemType, agentId, host, path, timestamp, size FROM loot;"):
            let (lootId, itemType, agentId, host, path, timestamp, size) = row.unpack((string, int, string, string, string, int64, int))

            let l = LootItem(
                lootId: lootId, 
                itemType: cast[LootItemType](itemType),
                agentId: agentId,
                host: host, 
                path: path,
                timestamp: timestamp, 
                size: size
            )

            loot.add(l)

        conquestDb.close()
    except: 
        cq.error(getCurrentExceptionMsg())

    return loot

proc dbGetLootById*(cq: Conquest, lootId: string): LootItem = 
    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)
        for row in conquestDb.iterate("SELECT lootId, itemType, agentId, host, path, timestamp, size FROM loot WHERE lootId = ?;", lootId):
            let (id, itemType, agentId, host, path, timestamp, size) = row.unpack((string, int, string, string, string, int64, int))
            result = LootItem(
                lootId: id,
                itemType: cast[LootItemType](itemType),
                agentId: agentId,
                host: host,
                path: path,
                timestamp: timestamp,
                size: size
            )
        conquestDb.close()
    except: 
        cq.error(getCurrentExceptionMsg())

proc dbDeleteLootById*(cq: Conquest, lootId: string): bool =
    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        conquestDb.exec("DELETE FROM loot WHERE lootId = ?", lootId)

        conquestDb.close()
    except: 
        return false
    
    return true