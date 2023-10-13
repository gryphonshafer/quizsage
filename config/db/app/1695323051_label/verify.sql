SELECT CASE WHEN
    ( SELECT 1 FROM sqlite_master WHERE type = 'table'   AND name = 'label'              ) +
    ( SELECT 1 FROM sqlite_master WHERE type = 'trigger' AND name = 'label_after_update' )
    = 2
THEN 1 ELSE 0 END;
