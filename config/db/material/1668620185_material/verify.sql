SELECT CASE WHEN
    ( SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'bible' ) +
    ( SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'book'  ) +
    ( SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'verse' )
    = 3
THEN 1 ELSE 0 END;
