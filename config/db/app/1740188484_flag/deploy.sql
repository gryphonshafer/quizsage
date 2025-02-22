-- dest.prereq: config/db/app/1668620185_user

CREATE TABLE IF NOT EXISTS flag (
    flag_id INTEGER PRIMARY KEY,
    user_id INTEGER NULL REFERENCES user(user_id) ON UPDATE CASCADE ON DELETE CASCADE,
    source  TEXT NOT NULL,
    url     TEXT NOT NULL,
    report  TEXT NOT NULL,
    data    TEXT    NOT NULL,
    created TEXT    NOT NULL DEFAULT ( STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' ) )
);
