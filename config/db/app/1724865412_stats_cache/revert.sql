ALTER TABLE season DROP COLUMN stats;

CREATE TABLE IF NOT EXISTS __NEW__meet (
    meet_id       INTEGER PRIMARY KEY,
    season_id     INTEGER NOT NULL REFERENCES season(season_id) ON UPDATE CASCADE ON DELETE CASCADE,
    name          TEXT NOT NULL CHECK( LENGTH(name) > 0 ),
    location      TEXT,
    start         TEXT NOT NULL DEFAULT ( STRFTIME( '%Y-%m-%d %H:%M-08:00', 'NOW', 'LOCALTIME' ) ),
    days          INTEGER NOT NULL DEFAULT 1,
    passwd        TEXT CHECK( passwd IS NULL OR LENGTH(passwd) >= 8 ),
    settings      TEXT,
    build         TEXT,
    last_modified TEXT NOT NULL DEFAULT ( STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' ) ),
    created       TEXT NOT NULL DEFAULT ( STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' ) )
);
INSERT INTO __NEW__meet (
    meet_id, season_id, name, location, start, days, passwd, settings, build, last_modified, created
) SELECT
    meet_id, season_id, name, location, start, days, passwd, settings, build, last_modified, created
FROM meet;
DROP TABLE meet;
ALTER TABLE __NEW__meet RENAME TO meet;
CREATE UNIQUE INDEX IF NOT EXISTS meet_identity ON meet ( season_id, name );
CREATE TRIGGER IF NOT EXISTS meet_last_modified
    AFTER UPDATE OF
        season_id,
        name,
        location,
        start,
        days,
        passwd,
        settings,
        build
    ON meet
    BEGIN
        UPDATE meet
            SET last_modified = STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' )
            WHERE meet_id = OLD.meet_id;
    END;
