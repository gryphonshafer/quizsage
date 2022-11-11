CREATE TABLE IF NOT EXISTS word (
    word_id     INTEGER PRIMARY KEY,
    redirect_id INTEGER NULL,
    text        TEXT    NOT NULL UNIQUE,
    meanings    TEXT    NULL,
    FOREIGN KEY (redirect_id) REFERENCES word(word_id) ON UPDATE CASCADE ON DELETE CASCADE
);
