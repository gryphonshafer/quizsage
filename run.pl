#!/usr/bin/env perl
use exact -conf;
use QuizSage::Util::Reference 'reference_data';

say reference_data(
    label     => 'Galatians; Ephesians; Philippians; Colossians ESV NIV',
    user_id   => 1,
    bible     => 'NIV',
    reference => 1,
    whole     => 5,
    chapter   => 3,
    phrases   => 4,
);
