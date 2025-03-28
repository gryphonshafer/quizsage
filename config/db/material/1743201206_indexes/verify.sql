SELECT CASE WHEN
    ( SELECT 1 FROM sqlite_master WHERE type = 'index' AND name = 'word_text'       ) +
    ( SELECT 1 FROM sqlite_master WHERE type = 'index' AND name = 'reverse_synonym' )
    = 2
THEN 1 ELSE 0 END;
