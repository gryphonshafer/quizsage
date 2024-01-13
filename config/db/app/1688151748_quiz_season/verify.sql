SELECT CASE WHEN
    ( SELECT 1 FROM sqlite_master WHERE type = 'table'   AND name = 'season'             ) +
    ( SELECT 1 FROM sqlite_master WHERE type = 'table'   AND name = 'meet'               ) +
    ( SELECT 1 FROM sqlite_master WHERE type = 'table'   AND name = 'quiz'               ) +
    ( SELECT 1 FROM sqlite_master WHERE type = 'trigger' AND name = 'meet_last_modified' ) +
    ( SELECT 1 FROM sqlite_master WHERE type = 'trigger' AND name = 'quiz_last_modified' )
    = 5
THEN 1 ELSE 0 END;
