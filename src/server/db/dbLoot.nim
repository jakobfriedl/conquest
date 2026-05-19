import system, terminal, tiny_sqlite
import ../core/logger
import ../../types/[common, server]

#[
    Loot database functions
]#

proc dbStoreLoot*(cq: Conquest, loot: LootItem): bool =
    try:
        cq.db.exec("INSERT OR REPLACE INTO loot VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
            loot.lootId, int(loot.itemType), loot.agentId, loot.host,
            loot.timestamp, loot.note, loot.path, loot.remotePath, loot.size,
            int(loot.credType), loot.username, loot.value)
    except:
        cq.error(getCurrentExceptionMsg())
        return false
    return true

proc dbGetLoot*(cq: Conquest): seq[LootItem] =
    try:
        let rows = cq.db.all("SELECT lootId, itemType, agentId, host, timestamp, note, path, remotePath, size, credType, username, value FROM loot;")
        for row in rows:
            let (lootId, itemType, agentId, host, timestamp, note, path, remotePath, size, credType, username, value) =
                row.unpack((string, int, string, string, int64, string, string, string, int, int, string, string))
            result.add(LootItem(
                lootId: lootId,
                itemType: cast[LootItemType](itemType),
                agentId: agentId,
                host: host,
                timestamp: timestamp,
                note: note,
                path: path,
                remotePath: remotePath,
                size: size,
                credType: cast[CredentialType](credType),
                username: username,
                value: value
            ))
    except:
        cq.error(getCurrentExceptionMsg())

proc dbGetLootById*(cq: Conquest, lootId: string): LootItem =
    try:
        let row = cq.db.one("SELECT lootId, itemType, agentId, host, timestamp, note, path, remotePath, size, credType, username, value FROM loot WHERE lootId = ?;", lootId)
        if row.isSome:
            let (id, itemType, agentId, host, timestamp, note, path, remotePath, size, credType, username, value) =
                row.get.unpack((string, int, string, string, int64, string, string, string, int, int, string, string))
            result = LootItem(
                lootId: id,
                itemType: cast[LootItemType](itemType),
                agentId: agentId,
                host: host,
                timestamp: timestamp,
                note: note,
                path: path,
                remotePath: remotePath,
                size: size,
                credType: cast[CredentialType](credType),
                username: username,
                value: value
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
