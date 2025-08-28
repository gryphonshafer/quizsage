#!/usr/bin/env perl
use exact -conf, -fun;
use DDP;
use lib '.';
use Label_v2;

my $label = Label_v2->new;
my $input = [
    q{
        Romans 1-5 (1) [ [ [ [ Romans 6-10 ] ] unrecognized text ] | Club [200] ] (1)
        [ James 5 ] (2)
        ~ Romans; James
        / Club (100) ~ Rom 2 (3) Club <300> (2) All (1)
        + 1 ~ Rom 3 | Rom 4
        ESV NIV NIV84*
    },
    'Romans 1-5 ESV',
];
$label->parse($_) for (@$input);
