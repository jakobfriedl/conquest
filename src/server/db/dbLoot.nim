import strutils, system, terminal, tiny_sqlite, pixie
import stb_image/write as stbiw
import ../core/logger
import ../../common/[types, utils]

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

proc createThumbnail*(data: string, maxWidth: int = 1024, quality: int = 90): string =
    let img: Image = decodeImage(data)
    
    let aspectRatio = img.height.float / img.width.float
    let 
        width = min(maxWidth, img.width)
        height = int(width.float * aspectRatio)

    # Resize image
    let thumbnail = img.resize(width, height)

    # Convert to JPEG image for smaller file size
    var rgbaData = newSeq[byte](width * height * 4)
    var i = 0
    for y in 0..<height:
        for x in 0..<width:
            let color = thumbnail[x, y]
            rgbaData[i] = color.r
            rgbaData[i + 1] = color.g
            rgbaData[i + 2] = color.b
            rgbaData[i + 3] = color.a
            i += 4
    
    return Bytes.toString(stbiw.writeJPG(width, height, 4, rgbaData, quality))

proc dbGetLoot*(cq: Conquest): seq[LootItem] = 
    var loot: seq[LootItem] = @[]

    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        for row in conquestDb.iterate("SELECT lootId, itemType, agentId, host, path, timestamp, size FROM loot;"):
            let (lootId, itemType, agentId, host, path, timestamp, size) = row.unpack((string, int, string, string, string, int64, int))

            var l = LootItem(
                lootId: lootId, 
                itemType: cast[LootItemType](itemType),
                agentId: agentId,
                host: host, 
                path: path,
                timestamp: timestamp, 
                size: size
            )

            if l.itemType == SCREENSHOT: 
                l.data = createThumbnail(readFile(path))    # Create a smaller thumbnail version of the screenshot for better transportability
            elif l.itemType == DOWNLOAD:
                l.data = readFile(path)                     # Read downloaded file
 
            loot.add(l)

        conquestDb.close()
    except: 
        cq.error(getCurrentExceptionMsg())

    return loot