SELECT CASE WHEN
    ( SELECT 1 FROM sqlite_master WHERE type = 'table'   AND name = 'season'           ) +
    ( SELECT 1 FROM sqlite_master WHERE type = 'table'   AND name = 'meet'             ) +
    ( SELECT 1 FROM sqlite_master WHERE type = 'index'   AND name = 'meet_identity'    ) +
    ( SELECT 1 FROM sqlite_master WHERE type = 'table'   AND name = 'quizzer'          ) +
    ( SELECT 1 FROM sqlite_master WHERE type = 'table'   AND name = 'registration'     ) +
    ( SELECT 1 FROM sqlite_master WHERE type = 'table'   AND name = 'quiz'             ) +
    ( SELECT 1 FROM sqlite_master WHERE type = 'index'   AND name = 'quizzer_identity' )
    = 7
THEN 1 ELSE 0 END;
