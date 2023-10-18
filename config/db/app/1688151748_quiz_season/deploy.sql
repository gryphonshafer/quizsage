-- dest.prereq: config/db/app/1668620185_user

CREATE TABLE IF NOT EXISTS season (
    season_id INTEGER PRIMARY KEY,
    name      TEXT    NOT NULL CHECK( LENGTH(name) > 0 ) UNIQUE
);

CREATE TABLE IF NOT EXISTS meet (
    meet_id   INTEGER PRIMARY KEY,
    season_id INTEGER NOT NULL REFERENCES season(season_id) ON UPDATE CASCADE ON DELETE CASCADE,
    name      TEXT    NOT NULL CHECK( LENGTH(name) > 0 )
);
CREATE UNIQUE INDEX IF NOT EXISTS meet_identity ON meet ( season_id, name );

CREATE TABLE IF NOT EXISTS quizzer (
    quizzer_id INTEGER PRIMARY KEY,
    name       TEXT     NOT NULL CHECK( LENGTH(name) > 0 ),
    m_f        TEXT     NOT NULL CHECK( m_f = 'M' OR m_f = 'F' OR m_f = 'X' ) DEFAULT 'X',
    birthdate  TEXT     NOT NULL DEFAULT 'X'
);
CREATE UNIQUE INDEX IF NOT EXISTS quizzer_identity ON quizzer ( name, m_f, birthdate );

CREATE TABLE IF NOT EXISTS registration (
    registration_id INTEGER PRIMARY KEY,
    meet_id         INTEGER NOT NULL REFERENCES meet(meet_id)       ON UPDATE CASCADE ON DELETE CASCADE,
    quizzer_id      INTEGER NOT NULL REFERENCES quizzer(quizzer_id) ON UPDATE CASCADE ON DELETE CASCADE,
    bible           TEXT    NOT NULL CHECK( LENGTH(bible) > 0 ),
    team            TEXT    NOT NULL,
    league          TEXT
);

CREATE TABLE IF NOT EXISTS quiz (
    quiz_id            INTEGER PRIMARY KEY,
    user_id            INTEGER NULL REFERENCES user(user_id) ON UPDATE CASCADE ON DELETE SET NULL,
    meet_id            INTEGER NULL REFERENCES meet(meet_id) ON UPDATE CASCADE ON DELETE CASCADE,
    name               TEXT    NOT NULL DEFAULT 'Quiz',
    password           TEXT,
    importmap          TEXT    NOT NULL,
    room               TEXT    NOT NULL DEFAULT 'Room',
    scheduled_start    TEXT    NOT NULL DEFAULT ( STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' ) ),
    scheduled_duration INTEGER NOT NULL DEFAULT 30,
    settings           TEXT,
    state              TEXT,
    last_modified      TEXT    NOT NULL DEFAULT ( STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' ) ),
    created            TEXT    NOT NULL DEFAULT ( STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' ) )
);
CREATE TRIGGER IF NOT EXISTS quiz_last_modified
    AFTER UPDATE OF
        user_id,
        meet_id,
        name,
        password,
        importmap,
        room,
        scheduled_start,
        scheduled_duration,
        settings,
        state
    ON quiz
    BEGIN
        UPDATE quiz
            SET last_modified = STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' )
            WHERE quiz_id = OLD.quiz_id;
    END;
