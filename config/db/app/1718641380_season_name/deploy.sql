-- dest.prereq: config/db/app/1688151748_quiz_season

CREATE TABLE IF NOT EXISTS __NEW__season (
    season_id INTEGER PRIMARY KEY,
    name      TEXT    NOT NULL CHECK( LENGTH(name) > 0 ),
    location  TEXT,
    start     TEXT    NOT NULL DEFAULT ( STRFTIME( '%Y-%m-%d %H:%M-08:00', 'NOW', 'LOCALTIME' ) ),
    days      INTEGER NOT NULL DEFAULT 365,
    settings  TEXT
);

INSERT INTO __NEW__season (
    season_id,
    name,
    location,
    start,
    days,
    settings
)
SELECT
    season_id,
    name,
    location,
    start,
    days,
    settings
FROM season;

DROP TABLE season;
ALTER TABLE __NEW__season RENAME TO season;

CREATE UNIQUE INDEX IF NOT EXISTS season_name_location ON season ( name, location );
