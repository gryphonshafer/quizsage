CREATE TABLE IF NOT EXISTS user (
    user_id       INTEGER PRIMARY KEY,
    username      TEXT NOT NULL UNIQUE,
    passwd        TEXT NOT NULL,
    first_name    TEXT,
    last_name     TEXT,
    email         TEXT NOT NULL UNIQUE,
    phone         TEXT,
    last_login    TEXT,
    last_modified TEXT NOT NULL DEFAULT ( STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' ) ),
    created       TEXT NOT NULL DEFAULT ( STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' ) ),
    active        INTEGER NOT NULL DEFAULT 0
);

CREATE TRIGGER IF NOT EXISTS user_after_update AFTER UPDATE OF
    username,
    passwd,
    first_name,
    last_name,
    email,
    phone,
    last_login,
    active
ON user
BEGIN
    UPDATE user SET last_modified = STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' )
    WHERE user_id = old.user_id;
END;
