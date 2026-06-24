import system, terminal, tiny_sqlite

import ./[dbAgent, dbListener, dbLoot, dbLink]
import ../core/logger
import ../../types/server

# Export functions so that only ./db/database is required to be imported
export dbAgent, dbListener, dbLoot, dbLink

proc dbInit*(cq: Conquest, dbPath: string) =
    
    cq.db = openDatabase(dbPath, mode=dbReadWrite)
    
    cq.db.exec("PRAGMA synchronous=NORMAL")
    cq.db.exec("PRAGMA foreign_keys=ON")
    
    cq.db.execScript("""
        CREATE TABLE IF NOT EXISTS listeners (
            listenerId          TEXT    PRIMARY KEY,
            listenerType        TEXT    NOT NULL,
            name                TEXT    NOT NULL DEFAULT '',
            hosts               TEXT,
            address             TEXT,
            port                INTEGER UNIQUE,
            pipe                TEXT,
            profile             TEXT
        );

        CREATE TABLE IF NOT EXISTS agents (
            agentId             TEXT    PRIMARY KEY,
            listenerId          TEXT    NOT NULL,
            process             TEXT    NOT NULL,
            pid                 INTEGER NOT NULL,
            username            TEXT    NOT NULL,
            impersonationToken  TEXT    NOT NULL,
            hostname            TEXT    NOT NULL,
            domain              TEXT    NOT NULL,
            ipInternal          TEXT    NOT NULL,
            ipExternal          TEXT    NOT NULL,
            os                  TEXT    NOT NULL,
            elevated            BOOLEAN NOT NULL,
            sleep               INTEGER NOT NULL,
            modules             INTEGER NOT NULL,
            firstCheckin        INTEGER NOT NULL,
            latestCheckin       INTEGER NOT NULL,
            sessionKey          BLOB    NOT NULL
        );

        CREATE TABLE IF NOT EXISTS loot (
            lootId              TEXT    PRIMARY KEY,
            itemType            INTEGER NOT NULL,
            agentId             TEXT    NOT NULL,
            host                TEXT    NOT NULL,
            timestamp           INTEGER NOT NULL,
            note                TEXT    NOT NULL DEFAULT '',
            path                TEXT    NOT NULL DEFAULT '',
            remotePath          TEXT    NOT NULL DEFAULT '',
            size                INTEGER NOT NULL DEFAULT 0,
            credType            INTEGER NOT NULL DEFAULT 0,
            username            TEXT    NOT NULL DEFAULT '',
            value               TEXT    NOT NULL DEFAULT ''
        );

        CREATE TABLE IF NOT EXISTS links (
            linkId              TEXT PRIMARY KEY,
            parentId            TEXT NOT NULL,
            childId             TEXT NOT NULL
        );
    """)
    cq.info("Using database: \"", dbPath, "\".\n")