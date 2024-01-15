SELECT CASE WHEN
    ( SELECT 1 FROM sqlite_master WHERE type = 'table'   AND name = 'user'              ) +
    ( SELECT 1 FROM sqlite_master WHERE type = 'trigger' AND name = 'user_last_modified' )
    = 2
THEN 1 ELSE 0 END;
