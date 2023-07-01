CREATE TABLE IF NOT EXISTS word (
    word_id     INTEGER PRIMARY KEY,
    redirect_id INTEGER REFERENCES word(word_id) ON UPDATE CASCADE ON DELETE CASCADE,
    text        TEXT    NOT NULL CHECK( LENGTH(text) > 0 ) UNIQUE,
    meanings    TEXT
);
