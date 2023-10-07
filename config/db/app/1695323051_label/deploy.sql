-- dest.prereq: config/db/app/1668620185_user

CREATE TABLE IF NOT EXISTS label (
    label_id      INTEGER PRIMARY KEY,
    user_id       INTEGER NULL REFERENCES user(user_id) ON UPDATE CASCADE ON DELETE SET NULL,
    name          TEXT    NOT NULL CHECK( LENGTH(name) > 0 ),
    label         TEXT    NOT NULL CHECK( LENGTH(name) > 0 ),
    public        INTEGER NOT NULL CHECK( public = 1 OR public = 0 ) DEFAULT 0,
    last_modified TEXT    NOT NULL DEFAULT ( STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' ) ),
    created       TEXT    NOT NULL DEFAULT ( STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' ) )
);
CREATE TRIGGER IF NOT EXISTS label_last_modified
    AFTER UPDATE OF
        user_id,
        name,
        label,
        public
    ON label
    BEGIN
        UPDATE label
            SET last_modified = STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' )
            WHERE label_id = OLD.label_id;
    END;
CREATE UNIQUE INDEX IF NOT EXISTS label_user_name ON label ( user_id, name );
CREATE TRIGGER IF NOT EXISTS label_null_user_update
    BEFORE UPDATE OF user_id, public
    ON label
    WHEN NEW.user_id IS NULL AND NOT NEW.public
    BEGIN
        UPDATE label SET public = 1 WHERE label_id = NEW.label_id;
    END;
CREATE TRIGGER IF NOT EXISTS label_null_user_insert
    AFTER INSERT
    ON label
    WHEN NEW.user_id IS NULL AND NOT NEW.public
    BEGIN
        UPDATE label SET public = 1 WHERE label_id = NEW.label_id;
    END;
