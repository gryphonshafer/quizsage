#!/usr/bin/env perl
use exact -conf;
use DDP;
use QuizSage::Model::Label;

my $label = QuizSage::Model::Label->new(
    user_id      => 1,
    user_aliases => [
        {
            name  => 'Club (100)',
            label => 'Rom 1:1-10',
            is_self_made => 0,
        },
        {
            name  => 'Club [200]',
            label => 'Rom 1:1-20',
            is_self_made => 0,
        },
        {
            name  => 'Club <300>',
            label => 'Rom 1:1-30',
            is_self_made => 0,
        },
    ],
);

for (
    'Romans 1-3; James 1:2-2:12',
    # 'Romans 1-3; James 1:2-2:12 (42)',
    # 'Romans 1-3 (40%) James 1:2-2:12 (60%)',
    # 'Romans 1-3; James 1:2-2:12 | Romans 2-6',
    # 'Romans 1-3 (40%) James 1:2-2:12 (60%) ~ Romans 2-6',
    # 'Romans 1-3 (40%) James 1:2-2:12 (60%) Romans 2-6 [ Romans 2-6 ]',
    # 'Romans 1-5 ~ Romans 4-7 (1)',
    # 'Romans 1-3 ~ Romans 2-6 (40%) James 1:2-2:12 +1 verse (60%)',
    # '[ Romans 1-5 (30%) Romans 6-10 (70%) ] +1 Verse',
    # 'Romans 1-5 [ Romans 6-10 | Romans 18 ] ~ Romans 4-7',
    # 'Romans 1-5 (3) [ [ Romans 6-10 ] | Romans 18 ] (1) ~ Romans 4-7',
    # 'James 2; Club (100); Romans 2 ~ Romans 1-3; Club [200]; James 1-3',
    # 'Romans 1 (1) / Club (100) (1)',
    # 'Romans 1-5 (1) Romans 6-10 (2) Romans 11-13 (3) / Club (100) (1) Club [200] (2) All (3)',
    # 'Romans 1-5 (1) Romans 6-10 (2) [ Romans 11-13 (3) / Club (100) (1) Club <300> (2) All (3) ]',
    # '[ Romans 1 (1) / Club (100) (1) ] / Club [200] (2)',
) {
    say '>>> ' . $_;
    my $r = $label->__parse($_); #. ' ESV NIV NIV84*' );
    p $r;
    # <STDIN>;
}
