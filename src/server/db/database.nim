import system, terminal, tiny_sqlite

import ./[dbAgent, dbListener, dbLoot]
import ../core/logger
import ../../common/types

# Export functions so that only ./db/database is required to be imported
export dbAgent, dbListener, dbLoot

proc dbInit*(cq: Conquest) =

    try: 
        let conquestDb = openDatabase(cq.dbPath, mode=dbReadWrite)

        # Create tables
        conquestDb.execScript("""
        CREATE TABLE listeners (
            listenerId TEXT PRIMARY KEY,
            hosts TEXT NOT NULL,
            address TEXT NOT NULL,
            port INTEGER NOT NULL UNIQUE,
            protocol TEXT NOT NULL CHECK (protocol IN ('http'))
        );

        CREATE TABLE agents (
            agentId TEXT PRIMARY KEY,                   
            listenerId TEXT NOT NULL, 
            process TEXT NOT NULL,                   
            pid INTEGER NOT NULL,
            username TEXT NOT NULL,
            impersonationToken TEXT NOT NULL,
            hostname TEXT NOT NULL,
            domain TEXT NOT NULL,
            ipInternal TEXT NOT NULL,
            ipExternal TEXT NOT NULL,
            os TEXT NOT NULL,
            elevated BOOLEAN NOT NULL,
            sleep INTEGER NOT NULL,
            modules INTEGER NOT NULL,
            firstCheckin INTEGER NOT NULL,
            latestCheckin INTEGER NOT NULL,
            sessionKey BLOB NOT NULL
        );

        CREATE TABLE loot (
            lootId TEXT PRIMARY KEY,
            itemType INTEGER NOT NULL, 
            agentId TEXT NOT NULL,
            host TEXT NOT NULL,
            path TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            size INTEGER NOT NULL 
        );

        """)
        
        cq.info("Using new database: \"", cq.dbPath, "\".\n")
        conquestDb.close()
    except SqliteError: 
        cq.info("Using existing database: \"", cq.dbPath, "\".\n")
