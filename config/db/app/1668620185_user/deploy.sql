CREATE TABLE IF NOT EXISTS user (
    user_id       INTEGER PRIMARY KEY,
    email         TEXT    NOT NULL CHECK( email LIKE '%_@__%.__%' ) UNIQUE,
    passwd        TEXT    NOT NULL CHECK( LENGTH(passwd)     > 8 ),
    first_name    TEXT    NOT NULL CHECK( LENGTH(first_name) > 0 ),
    last_name     TEXT    NOT NULL CHECK( LENGTH(last_name)  > 0 ),
    phone         TEXT    NOT NULL CHECK( LENGTH(phone)      > 0 ),
    settings      TEXT,
    last_login    TEXT,
    last_modified TEXT    NOT NULL DEFAULT ( STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' ) ),
    created       TEXT    NOT NULL DEFAULT ( STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' ) ),
    active        INTEGER NOT NULL CHECK( active = 1 OR active = 0 ) DEFAULT 0
);
CREATE TRIGGER IF NOT EXISTS user_after_update AFTER UPDATE OF
    email,
    passwd,
    first_name,
    last_name,
    phone,
    settings,
    last_login,
    active
ON user
BEGIN
    UPDATE user SET last_modified = STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' )
    WHERE user_id = old.user_id;
END;
