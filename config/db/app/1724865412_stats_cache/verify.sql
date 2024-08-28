SELECT CASE WHEN
    ( SELECT COUNT(*) FROM sqlite_master WHERE name = 'season' AND sql REGEXP '\bstats\s+TEXT\b' ) +
    ( SELECT COUNT(*) FROM sqlite_master WHERE name = 'meet' AND sql REGEXP '\bstats\s+TEXT\b' )
    = 2
THEN 1 ELSE 0 END;
