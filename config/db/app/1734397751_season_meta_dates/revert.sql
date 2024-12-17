DROP TRIGGER IF EXISTS season_last_modified;
CREATE TABLE IF NOT EXISTS __NEW__season (
    season_id INTEGER PRIMARY KEY,
    user_id   INTEGER REFERENCES user(user_id) ON UPDATE CASCADE ON DELETE SET NULL,
    name      TEXT NOT NULL CHECK( LENGTH(name) > 0 ),
    location  TEXT,
    start     TEXT NOT NULL DEFAULT ( STRFTIME( '%Y-%m-%d %H:%M-08:00', 'NOW', 'LOCALTIME' ) ),
    days      INTEGER NOT NULL DEFAULT 365,
    settings  TEXT,
    stats     TEXT,
    active    INTEGER NOT NULL CHECK( active = 1 OR active = 0 ) DEFAULT 1
);
INSERT INTO __NEW__season (
    season_id, user_id, name, location, start, days, settings, stats, active
) SELECT
    season_id, user_id, name, location, start, days, settings, stats, active
FROM season;
DROP TABLE season;
ALTER TABLE __NEW__season RENAME TO season;
CREATE UNIQUE INDEX IF NOT EXISTS season_name_location ON season ( name, location );
