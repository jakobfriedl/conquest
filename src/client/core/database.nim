import tiny_sqlite 
import ../utils/globals

proc dbInit*() = 
    try: 
        let clientDb = openDatabase(CONQUEST_ROOT & "/data/client.db", mode=dbReadWrite)
        clientDb.execScript("""

            CREATE TABLE IF NOT EXISTS modules ( 
                name TEXT PRIMARY KEY,
                path TEXT NOT NULL
            ); 

        """)
        clientDb.close() 

    except SqliteError as err: 
        echo "[-] " & err.msg
    
proc dbStoreModule*(name, path: string): bool = 
    try: 
        let clientDb = openDatabase(CONQUEST_ROOT & "/data/client.db", mode=dbReadWrite)
        clientDb.exec("INSERT INTO modules (name, path) VALUES (?, ?);", name, path)
        clientDb.close() 

    except: 
        echo "[-] " & getCurrentExceptionMsg()
        return false
    
    return true

proc dbRemoveModule*(name: string): bool = 
    try: 
        let clientDb = openDatabase(CONQUEST_ROOT & "/data/client.db", mode=dbReadWrite)
        clientDb.exec("DELETE FROM modules WHERE name = ?", name)
        clientDb.close()
        
    except: 
        echo "[-] " & getCurrentExceptionMsg()
        return false
    
    return true

proc dbModuleExists*(name: string): bool =
    try:
        let clientDb = openDatabase(CONQUEST_ROOT & "/data/client.db", mode=dbReadWrite)
        let res = clientDb.one("SELECT 1 FROM modules WHERE name = ? LIMIT 1", name)
        clientDb.close()
        return res.isSome

    except:
        echo "[-] " & getCurrentExceptionMsg()
        return false

proc dbGetScriptPaths*(): seq[string] = 
    try: 
        let clientDb = openDatabase(CONQUEST_ROOT & "/data/client.db", mode=dbReadWrite)
        for row in clientDb.iterate("SELECT DISTINCT path FROM modules;"):
            let (path,) = row.unpack((string,))
            result.add(path)
        clientDb.close()

    except: 
        echo "[-] " & getCurrentExceptionMsg()