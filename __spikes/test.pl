#!/usr/bin/env perl
use exact -conf;
use DDP;
use QuizSage::Model::Label;

my $label = QuizSage::Model::Label->new(
    user_id      => 1,
    user_aliases => [
        {
            name  => 'Club (10)',
            label => 'Rom 1:1-10',
        },
        {
            name  => 'Club [20]',
            label => 'Rom 1:1-20',
        },
        {
            name  => 'Club <30>',
            label => 'Rom 1:1-30',
        },
        {
            name  => 'Very Early Cor',
            label => '1 Corinthians 1-2',
        },
        {
            name  => 'Early Cor',
            label => '1 Corinthians 3-4; Very Early Cor',
        },
    ],
);

for (
    'Romans 1-3; James 1:2-2:12',
    'Romans 1-3; James 1:2-2:12 (42)',
    'Romans 1-3 (40%) James 1:2-2:12 (60%)',
    'Romans 1-3; James 1:2-2:12 | Romans 2-6',
    'Romans 1-3 (40%) James 1:2-2:12 (60%) ~ Romans 2-6',
    'Romans 1-3 (40%) James 1:2-2:12 (60%) Romans 2-6 [ Romans 2-6 ]',
    'Romans 1-5 ~ Romans 4-7 (1)',
    'Romans 1-3 ~ Romans 2-6 (40%) James 1:2-2:12 +1 verse (60%)',
    '[ Romans 1-5 (30%) Romans 6-10 (70%) ] +1 Verse',
    'Romans 1-5 [ Romans 6-10 | Romans 18 ] ~ Romans 4-7',
    'Romans 1-5 (3) [ [ Romans 6-10 ] | Romans 18 ] (1) ~ Romans 4-7',
    '1 Cor | Early Cor',
    'James 2; Club (10); Romans 2 ~ Romans 1-3; Club [20]; James 1-3',
    'Romans 1 (1) / Club (10) (1)',
    'Romans 1-5 (1) Romans 6-10 (2) Romans 11-13 (3) / Club (10) (1) Club [20] (2) All (3)',
    'Romans 1-5 (1) Romans 6-10 (2) [ Romans 11-13 (3) / Club (10) (1) Club <30> (2) All (3) ]',
    '[ Romans 1 (1) / Club (10) (1) ] / Club [20] (2)',
) {
    say '>>> ' . $_;
    my $r = $label->__parse($_); #. ' ESV NIV NIV84*' );
    p $r;
    <STDIN>;
}
