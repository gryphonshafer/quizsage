SELECT CASE WHEN
    ( SELECT COUNT(*) FROM sqlite_master WHERE name = 'season' AND sql REGEXP '\bhidden\s+INTEGER\b' ) +
    ( SELECT COUNT(*) FROM sqlite_master WHERE name = 'meet' AND sql REGEXP '\bhidden\s+INTEGER\b' )
    = 2
THEN 1 ELSE 0 END;
