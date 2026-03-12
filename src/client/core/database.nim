import tiny_sqlite 
import ../utils/globals

proc dbInit*() = 
    try: 
        let clientDb = openDatabase(CONQUEST_ROOT & "/data/client.db", mode=dbReadWrite)
        clientDb.execScript("""

            CREATE TABLE IF NOT EXISTS scripts ( 
                path TEXT NOT NULL
            ); 

        """)
        clientDb.close() 

    except SqliteError as err: 
        echo "[-] " & err.msg
    
proc dbStoreScript*(path: string): bool = 
    try: 
        let clientDb = openDatabase(CONQUEST_ROOT & "/data/client.db", mode=dbReadWrite)
        clientDb.exec("INSERT INTO scripts (path) VALUES (?);", path)
        clientDb.close() 

    except: 
        echo "[-] " & getCurrentExceptionMsg()
        return false
    
    return true

proc dbRemoveScript*(path: string): bool = 
    try: 
        let clientDb = openDatabase(CONQUEST_ROOT & "/data/client.db", mode=dbReadWrite)
        clientDb.exec("DELETE FROM scripts WHERE path = ?", path)
        clientDb.close()
        
    except: 
        echo "[-] " & getCurrentExceptionMsg()
        return false
    
    return true

proc dbScriptExists*(path: string): bool =
    try:
        let clientDb = openDatabase(CONQUEST_ROOT & "/data/client.db", mode=dbReadWrite)
        let res = clientDb.one("SELECT 1 FROM scripts WHERE path = ? LIMIT 1", path)
        clientDb.close()
        return res.isSome

    except:
        echo "[-] " & getCurrentExceptionMsg()
        return false

proc dbGetScriptPaths*(): seq[string] = 
    try: 
        let clientDb = openDatabase(CONQUEST_ROOT & "/data/client.db", mode=dbReadWrite)
        let rows = clientDb.all("SELECT DISTINCT path FROM scripts;")
        clientDb.close()
        for row in rows:
            let (path,) = row.unpack((string,))
            result.add(path)
    except: 
        echo "[-] " & getCurrentExceptionMsg()