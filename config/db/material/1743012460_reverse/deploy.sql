-- dest.prereq: config/db/material/1668625906_thesaurus

CREATE TABLE IF NOT EXISTS reverse (
    reverse_id INTEGER PRIMARY KEY,
    word_id    INTEGER REFERENCES word(word_id) ON UPDATE CASCADE ON DELETE CASCADE,
    synonym    TEXT NOT NULL CHECK( LENGTH(synonym) > 0 ),
    verity     INTEGER NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS reverse_word_synonym ON reverse ( word_id, synonym );
