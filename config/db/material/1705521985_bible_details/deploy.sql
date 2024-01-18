-- dest.prereq: config/db/material/1668620185_material

ALTER TABLE bible ADD COLUMN label TEXT;
ALTER TABLE bible ADD COLUMN name TEXT;
ALTER TABLE bible ADD COLUMN year TEXT;

UPDATE bible SET label = acronym;
