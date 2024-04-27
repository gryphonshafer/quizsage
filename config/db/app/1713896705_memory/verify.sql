SELECT CASE WHEN
    ( SELECT 1 FROM sqlite_master WHERE type = 'table'   AND name = 'memory'               ) +
    ( SELECT 1 FROM sqlite_master WHERE type = 'trigger' AND name = 'memory_last_modified' ) +
    ( SELECT 1 FROM sqlite_master WHERE type = 'table'   AND name = 'shared_memory'        )
    = 3
THEN 1 ELSE 0 END;
