CREATE TABLE IF NOT EXISTS bible (
    bible_id INTEGER PRIMARY KEY,
    acronym  TEXT    NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS book (
    book_id INTEGER PRIMARY KEY,
    name    TEXT    NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS verse (
    verse_id       INTEGER PRIMARY KEY,
    bible_id INTEGER NOT NULL,
    book_id        INTEGER NOT NULL,
    chapter        INTEGER NOT NULL,
    verse          INTEGER NOT NULL,
    text           TEXT    NOT NULL, -- "This is a sentence. This is another sentence."
    string         TEXT    NOT NULL, -- "this is a sentence this is another sentence"
    FOREIGN KEY (bible_id) REFERENCES bible(bible_id) ON UPDATE CASCADE ON DELETE CASCADE,
    FOREIGN KEY (book_id)  REFERENCES book(book_id)   ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE UNIQUE INDEX verse_reference ON verse ( bible_id, book_id, chapter, verse );
