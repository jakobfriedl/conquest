import system, terminal, tiny_sqlite
import ../core/logger
import ../../types/[common, server, event]

#[
    Loot database functions
]#

proc dbStoreLoot*(cq: Conquest, loot: LootItem): bool = 
    try: 
        cq.db.exec("""
        INSERT INTO loot (lootId, itemType, agentId, host, path, timestamp, size)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """, loot.lootId, int(loot.itemType), loot.agentId, loot.host, loot.path, loot.timestamp, loot.size)
    except: 
        cq.error(getCurrentExceptionMsg())
        return false
    return true

proc dbGetLoot*(cq: Conquest): seq[LootItem] = 
    try:
        let rows = cq.db.all("SELECT lootId, itemType, agentId, host, path, timestamp, size FROM loot;")
        for row in rows:
            let (lootId, itemType, agentId, host, path, timestamp, size) = row.unpack((string, int, string, string, string, int64, int))
            result.add(LootItem(
                lootId: lootId, 
                itemType: cast[LootItemType](itemType),
                agentId: agentId,
                host: host, 
                path: path,
                timestamp: timestamp, 
                size: size
            ))
    except: 
        cq.error(getCurrentExceptionMsg())

proc dbGetLootById*(cq: Conquest, lootId: string): LootItem = 
    try:
        let row = cq.db.one("SELECT lootId, itemType, agentId, host, path, timestamp, size FROM loot WHERE lootId = ?;", lootId)
        if row.isSome:
            let (id, itemType, agentId, host, path, timestamp, size) = row.get.unpack((string, int, string, string, string, int64, int))
            result = LootItem(
                lootId: id,
                itemType: cast[LootItemType](itemType),
                agentId: agentId,
                host: host,
                path: path,
                timestamp: timestamp,
                size: size
            )
    except: 
        cq.error(getCurrentExceptionMsg())

proc dbDeleteLootById*(cq: Conquest, lootId: string): bool =
    try: 
        cq.db.exec("DELETE FROM loot WHERE lootId = ?", lootId)
    except: 
        cq.error(getCurrentExceptionMsg())
        return false
    return true