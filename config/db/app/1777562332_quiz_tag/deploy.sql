-- dest.prereq: config/db/app/1743201206_indexes

ALTER TABLE quiz RENAME TO __OLD__quiz;

CREATE TABLE IF NOT EXISTS quiz (
    quiz_id       INTEGER PRIMARY KEY,
    meet_id       INTEGER NULL REFERENCES meet(meet_id) ON UPDATE CASCADE ON DELETE CASCADE,
    user_id       INTEGER NULL REFERENCES user(user_id) ON UPDATE CASCADE ON DELETE SET NULL,
    bracket       TEXT,
    name          TEXT,
    tag           TEXT    NULL DEFAULT NULL,
    settings      TEXT,
    state         TEXT,
    last_modified TEXT    NOT NULL DEFAULT ( STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' ) ),
    created       TEXT    NOT NULL DEFAULT ( STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' ) )
);

INSERT INTO quiz ( quiz_id, meet_id, user_id, bracket, name, tag, settings, state, last_modified, created )
    SELECT quiz_id, meet_id, user_id, bracket, name, NULL, settings, state, last_modified, created
    FROM __OLD__quiz;

CREATE INDEX IF NOT EXISTS quiz_meet_id ON quiz (meet_id);
CREATE INDEX IF NOT EXISTS quiz_user_id ON quiz (user_id);

CREATE TRIGGER IF NOT EXISTS quiz_last_modified
    AFTER UPDATE OF
        meet_id,
        user_id,
        bracket,
        name,
        settings,
        state
    ON quiz
    BEGIN
        UPDATE quiz
            SET last_modified = STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' )
            WHERE quiz_id = OLD.quiz_id;
    END;

DROP TABLE __OLD__quiz;
