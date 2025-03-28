-- dest.prereq: config/db/material/1743012460_reverse

CREATE INDEX IF NOT EXISTS word_text ON word (text);
CREATE INDEX IF NOT EXISTS reverse_synonym ON reverse (synonym);
