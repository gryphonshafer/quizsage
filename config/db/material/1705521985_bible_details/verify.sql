SELECT CASE WHEN
    ( SELECT COUNT(*) FROM pragma_table_info('bible') WHERE name IN ( 'label', 'name', 'year' ) )
    = 3
THEN 1 ELSE 0 END;
