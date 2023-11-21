-- dest.prereq: config/db/app/1668620185_user

CREATE TABLE IF NOT EXISTS season (
    season_id INTEGER PRIMARY KEY,
    name      TEXT    NOT NULL CHECK( LENGTH(name) > 0 ) UNIQUE,
    start     TEXT    NOT NULL DEFAULT ( STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' ) ),
    days      INTEGER NOT NULL DEFAULT 365,
    settings  TEXT
);

CREATE TABLE IF NOT EXISTS meet (
    meet_id       INTEGER PRIMARY KEY,
    season_id     INTEGER NOT NULL REFERENCES season(season_id) ON UPDATE CASCADE ON DELETE CASCADE,
    name          TEXT    NOT NULL CHECK( LENGTH(name) > 0 ),
    location      TEXT
    start         TEXT    NOT NULL DEFAULT ( STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' ) ),
    days          INTEGER NOT NULL DEFAULT 365,
    settings      TEXT,
    state         TEXT,
    last_modified TEXT    NOT NULL DEFAULT ( STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' ) ),
    created       TEXT    NOT NULL DEFAULT ( STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' ) )
);
CREATE UNIQUE INDEX IF NOT EXISTS meet_identity ON meet ( season_id, name );
CREATE TRIGGER IF NOT EXISTS meet_last_modified
    AFTER UPDATE OF
        season_id,
        name,
        location,
        start,
        days,
        settings,
        state
    ON meet
    BEGIN
        UPDATE meet
            SET last_modified = STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' )
            WHERE meet_id = OLD.meet_id;
    END;

CREATE TABLE IF NOT EXISTS quiz (
    quiz_id            INTEGER PRIMARY KEY,
    meet_id            INTEGER NULL REFERENCES meet(meet_id) ON UPDATE CASCADE ON DELETE CASCADE,
    name               TEXT,
    room               TEXT,
    settings           TEXT,
    state              TEXT,
    last_modified      TEXT    NOT NULL DEFAULT ( STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' ) ),
    created            TEXT    NOT NULL DEFAULT ( STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' ) )
);
CREATE TRIGGER IF NOT EXISTS quiz_last_modified
    AFTER UPDATE OF
        meet_id,
        name,
        room,
        settings,
        state
    ON quiz
    BEGIN
        UPDATE quiz
            SET last_modified = STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' )
            WHERE quiz_id = OLD.quiz_id;
    END;
