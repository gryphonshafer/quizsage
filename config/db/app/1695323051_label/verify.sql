SELECT CASE WHEN
    ( SELECT 1 FROM sqlite_master WHERE type = 'table'   AND name = 'label'                  ) +
    ( SELECT 1 FROM sqlite_master WHERE type = 'trigger' AND name = 'label_last_modified'    ) +
    ( SELECT 1 FROM sqlite_master WHERE type = 'trigger' AND name = 'label_null_user_update' ) +
    ( SELECT 1 FROM sqlite_master WHERE type = 'trigger' AND name = 'label_null_user_insert' )
    = 4
THEN 1 ELSE 0 END;
