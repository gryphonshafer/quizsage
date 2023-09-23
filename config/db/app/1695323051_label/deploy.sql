-- dest.prereq: config/db/app/1668620185_user

CREATE TABLE IF NOT EXISTS label (
    label_id      INTEGER PRIMARY KEY,
    user_id       INTEGER NULL REFERENCES user(user_id) ON UPDATE CASCADE ON DELETE SET NULL,
    name          TEXT    NOT NULL,
    label         TEXT    NOT NULL,
    public        INTEGER NOT NULL CHECK( public = 1 OR public = 0 ) DEFAULT 0,
    last_modified TEXT    NOT NULL DEFAULT ( STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' ) ),
    created       TEXT    NOT NULL DEFAULT ( STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' ) )
);
CREATE TRIGGER IF NOT EXISTS label_after_update AFTER UPDATE OF
    user_id,
    name,
    label,
    public
ON label
BEGIN
    UPDATE label SET last_modified = STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' )
    WHERE label_id = old.label_id;
END;
