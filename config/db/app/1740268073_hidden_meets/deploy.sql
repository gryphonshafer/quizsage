-- dest.prereq: config/db/app/1734397751_season_meta_dates

CREATE TABLE IF NOT EXISTS __NEW__season (
    season_id     INTEGER PRIMARY KEY,
    user_id       INTEGER REFERENCES user(user_id) ON UPDATE CASCADE ON DELETE SET NULL,
    name          TEXT NOT NULL CHECK( LENGTH(name) > 0 ),
    location      TEXT,
    start         TEXT NOT NULL DEFAULT ( STRFTIME( '%Y-%m-%d %H:%M-08:00', 'NOW', 'LOCALTIME' ) ),
    days          INTEGER NOT NULL DEFAULT 365,
    settings      TEXT,
    stats         TEXT,
    last_modified TEXT NOT NULL DEFAULT ( STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' ) ),
    created       TEXT NOT NULL DEFAULT ( STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' ) ),
    hidden        INTEGER NOT NULL CHECK( hidden = 1 OR hidden = 0 ) DEFAULT 0,
    active        INTEGER NOT NULL CHECK( active = 1 OR active = 0 ) DEFAULT 1
);
INSERT INTO __NEW__season (
    season_id, user_id, name, location, start, days, settings, stats, active
) SELECT
    season_id, user_id, name, location, start, days, settings, stats, active
FROM season;
DROP TABLE season;
ALTER TABLE __NEW__season RENAME TO season;
CREATE UNIQUE INDEX IF NOT EXISTS season_name_location ON season ( name, location );
CREATE TRIGGER IF NOT EXISTS season_last_modified
    AFTER UPDATE OF
        user_id,
        name,
        location,
        start,
        days,
        settings,
        stats,
        hidden,
        active
    ON season
    BEGIN
        UPDATE season
            SET last_modified = STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' )
            WHERE season_id = OLD.season_id;
    END;

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
    stats         TEXT,
    last_modified TEXT NOT NULL DEFAULT ( STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' ) ),
    created       TEXT NOT NULL DEFAULT ( STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' ) ),
    hidden        INTEGER NOT NULL CHECK( hidden = 1 OR hidden = 0 ) DEFAULT 0
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
        build,
        stats,
        hidden
    ON meet
    BEGIN
        UPDATE meet
            SET last_modified = STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' )
            WHERE meet_id = OLD.meet_id;
    END;
