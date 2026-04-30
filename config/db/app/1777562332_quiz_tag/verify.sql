SELECT CASE WHEN
    ( SELECT COUNT(*) FROM sqlite_master WHERE name = 'quiz' AND sql REGEXP '\btag\s+TEXT\b' )
    = 1
THEN 1 ELSE 0 END;
