export const min_verity_level = 3;

export const default_query_settings = {
    phrase_min_prompt_length: 6,
    phrase_min_reply_length : 2,
    cr_min_prompt_length    : { key: 3, extra: 3 },
    cr_min_reply_length     : 2,
    finish_prompt_length    : 5,
    finish_min_reply_length : 2,
    xr_min_prompt_length    : 4,
    xr_min_references       : 2,
};

export const score_points = {
    open_book           : 1,
    synonymous          : 2,
    verbatim            : 4,
    with_reference      : 1,
    add_verse_synonymous: 1,
    add_verse_verbatim  : 2,
    ceiling             : 3,
    follow              : 1,
    nth_quizzer_bonus   : 1,
};

export const distribution_query_types      = [ 'P', 'C', 'Q', 'F' ];
export const timeouts_per_team             = 1;
export const max_appeals_declined_per_team = 2;

export const quizzer_response_duration = 40;
export const timeout_duration          = 40;
