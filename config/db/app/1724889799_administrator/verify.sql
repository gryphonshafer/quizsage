SELECT CASE WHEN
    ( SELECT COUNT(*) FROM sqlite_master WHERE name = 'season' AND sql REGEXP '\buser_id\s+INTEGER\b' ) +
    ( SELECT 1 FROM sqlite_master WHERE type = 'table'   AND name = 'administrator' )
    = 2
THEN 1 ELSE 0 END;
