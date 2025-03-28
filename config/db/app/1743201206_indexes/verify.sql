SELECT CASE WHEN
    ( SELECT 1 FROM sqlite_master WHERE type = 'index' AND name = 'meet_season_id' ) +
    ( SELECT 1 FROM sqlite_master WHERE type = 'index' AND name = 'quiz_meet_id'   ) +
    ( SELECT 1 FROM sqlite_master WHERE type = 'index' AND name = 'quiz_user_id'   )
    = 3
THEN 1 ELSE 0 END;
