import system, terminal, tiny_sqlite
import ../types
import ./[dbAgent, dbListener]

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
            jitter REAL DEFAULT 0.1,
            firstCheckin DATETIME NOT NULL,
            FOREIGN KEY (listener) REFERENCES listeners(name)
        );

        """)
        
        cq.writeLine(fgGreen, "[+] ", cq.dbPath, ": Database created.")
        conquestDb.close()
    except SqliteError: 
        cq.writeLine(fgGreen, "[+] ", cq.dbPath, ": Database file found.")
