-- dest.prereq: config/db/material/1668620185_material

CREATE TABLE IF NOT EXISTS popularity (
    popularity_id INTEGER PRIMARY KEY,
    book_id       INTEGER NOT NULL REFERENCES book(book_id) ON UPDATE CASCADE ON DELETE CASCADE,
    chapter       INTEGER NOT NULL CHECK( chapter      > 0 ),
    verse         INTEGER NOT NULL CHECK( verse        > 0 ),
    popularity    REAL    NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS popularity_reference ON popularity ( book_id, chapter, verse );
