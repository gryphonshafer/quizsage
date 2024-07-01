SELECT CASE WHEN
    ( SELECT COUNT(*) FROM sqlite_master WHERE name = 'season' AND sql REGEXP '\bname\s+TEXT\b' ) +
    ( SELECT COUNT(*) FROM sqlite_master WHERE name = 'season' AND sql REGEXP '\bname\s+TEXT\b[^,]+UNIQUE,' )
    = 1
THEN 1 ELSE 0 END;
