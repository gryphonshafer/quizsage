SELECT CASE WHEN
    ( SELECT 1 FROM sqlite_master WHERE type = 'table'   AND name = 'season' ) +
    ( SELECT 1 FROM sqlite_master WHERE type = 'table'   AND name = 'meet'   ) +
    ( SELECT 1 FROM sqlite_master WHERE type = 'table'   AND name = 'quiz'   )
    = 3
THEN 1 ELSE 0 END;
