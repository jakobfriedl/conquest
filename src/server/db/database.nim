import system, terminal, tiny_sqlite

import ./[dbAgent, dbListener]
import ../utils
import ../../common/[types, utils]

# Export functions so that only ./db/database is required to be imported
export dbAgent, dbListener

proc dbInit*(cq: Conquest) =

    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        # Create tables
        conquestDb.execScript("""
        CREATE TABLE listeners (
            name TEXT PRIMARY KEY,
            address TEXT NOT NULL,
            port INTEGER NOT NULL UNIQUE,
            protocol TEXT NOT NULL CHECK (protocol IN ('http'))
        );

        CREATE TABLE agents (
            name TEXT PRIMARY KEY,                   
            listener TEXT NOT NULL, 
            process TEXT NOT NULL,                   
            pid INTEGER NOT NULL,
            username TEXT NOT NULL,
            hostname TEXT NOT NULL,
            domain TEXT NOT NULL,
            ip TEXT NOT NULL,
            os TEXT NOT NULL,
            elevated BOOLEAN NOT NULL,
            sleep INTEGER DEFAULT 10,
            firstCheckin DATETIME NOT NULL,
            latestCheckin DATETIME NOT NULL,
            sessionKey BLOB NOT NULL, 
            FOREIGN KEY (listener) REFERENCES listeners(name)
        );

        """)
        
        cq.writeLine(fgBlack, styleBright, "[*] Using new database: \"", cq.dbPath, "\".\n")
        conquestDb.close()
    except SqliteError as err: 
        cq.writeLine(fgBlack, styleBright, "[*] Using existing database: \"", cq.dbPath, "\".\n")
