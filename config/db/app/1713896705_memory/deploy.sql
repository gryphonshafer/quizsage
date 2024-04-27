-- dest.prereq: config/db/app/1668620185_user

CREATE TABLE IF NOT EXISTS memory (
    memory_id     INTEGER PRIMARY KEY,
    user_id       INTEGER NOT NULL REFERENCES user(user_id) ON UPDATE CASCADE ON DELETE CASCADE,
    book          TEXT    NOT NULL,
    chapter       INTEGER NOT NULL,
    verse         INTEGER NOT NULL,
    bible         TEXT    NOT NULL,
    level         INTEGER NOT NULL DEFAULT 0,
    last_modified TEXT    NOT NULL DEFAULT ( STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' ) ),
    created       TEXT    NOT NULL DEFAULT ( STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' ) )
);
CREATE UNIQUE INDEX IF NOT EXISTS memory_reference ON memory (
    user_id,
    book,
    chapter,
    verse,
    bible
);
CREATE TRIGGER IF NOT EXISTS memory_last_modified
    AFTER UPDATE OF
        user_id,
        book,
        chapter,
        verse,
        bible,
        level
    ON memory
    BEGIN
        UPDATE memory
            SET last_modified = STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' )
            WHERE memory_id = OLD.memory_id;
    END;

CREATE TABLE IF NOT EXISTS shared_memory (
    shared_memory_id  INTEGER PRIMARY KEY,
    memorizer_user_id INTEGER NOT NULL REFERENCES user(user_id) ON UPDATE CASCADE ON DELETE CASCADE,
    shared_user_id    INTEGER NOT NULL REFERENCES user(user_id) ON UPDATE CASCADE ON DELETE CASCADE,
    created           TEXT    NOT NULL DEFAULT ( STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' ) )
);
CREATE UNIQUE INDEX IF NOT EXISTS shared_memory_users ON shared_memory ( memorizer_user_id, shared_user_id );
