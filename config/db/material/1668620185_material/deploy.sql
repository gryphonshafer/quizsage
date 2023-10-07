CREATE TABLE IF NOT EXISTS bible (
    bible_id INTEGER PRIMARY KEY,
    acronym  TEXT    NOT NULL CHECK( LENGTH(acronym) > 0 ) UNIQUE
);

CREATE TABLE IF NOT EXISTS book (
    book_id INTEGER PRIMARY KEY,
    name    TEXT    NOT NULL CHECK( LENGTH(name) > 0 ) UNIQUE
);

CREATE TABLE IF NOT EXISTS verse (
    verse_id INTEGER PRIMARY KEY,
    bible_id INTEGER NOT NULL REFERENCES bible(bible_id) ON UPDATE CASCADE ON DELETE CASCADE,
    book_id  INTEGER NOT NULL REFERENCES book(book_id)   ON UPDATE CASCADE ON DELETE CASCADE,
    chapter  INTEGER NOT NULL CHECK( chapter      > 0 ),
    verse    INTEGER NOT NULL CHECK( verse        > 0 ),
    text     TEXT    NOT NULL CHECK( LENGTH(text) > 0 )
);
CREATE UNIQUE INDEX IF NOT EXISTS verse_reference ON verse ( bible_id, book_id, chapter, verse );
