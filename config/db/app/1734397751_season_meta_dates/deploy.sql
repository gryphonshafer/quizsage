-- dest.prereq: config/db/app/1724865412_stats_cache

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
        active
    ON season
    BEGIN
        UPDATE season
            SET last_modified = STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' )
            WHERE season_id = OLD.season_id;
    END;
