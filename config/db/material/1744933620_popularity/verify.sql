SELECT CASE WHEN
    ( SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'popularity' )
    = 1
THEN 1 ELSE 0 END;
