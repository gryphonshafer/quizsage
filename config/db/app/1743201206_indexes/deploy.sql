-- dest.prereq: config/db/app/1740268073_hidden_meets

CREATE INDEX IF NOT EXISTS meet_season_id ON meet (season_id);
CREATE INDEX IF NOT EXISTS quiz_meet_id ON quiz (meet_id);
CREATE INDEX IF NOT EXISTS quiz_user_id ON quiz (user_id);
