use Test2::V0;
use exact -conf;
use QuizSage::Model::Label;

my $obj;
ok( lives { $obj = QuizSage::Model::Label->new }, 'new' ) or note $@;
DOES_ok( $obj, 'Omniframe::Role::Model' );
can_ok( $obj, qw(
    user_id user_aliases bible_ref bible_acronyms
    aliases parse canonicalize descriptionize
) );

ref_ok( $obj->aliases, 'ARRAY', 'aliases returns arrayref' );
ref_ok( $obj->bible_acronyms, 'ARRAY', 'bible_acronyms returns arrayref' );

done_testing;
exit;

my $mock = mock 'QuizSage::Model::Label' => (
    override => [
        bible_acronyms => sub { [ qw( ESV NASB NIV ) ] },
        aliases        => sub { [
            {
                name  => 'Wisdom Verses',
                label => 'James 1:5-8',
            },
            {
                name  => 'Awesome Verses',
                label => 'Ephesians 6:10-17; Wisdom Verses',
            },
        ] },
    ],
);

for (
    [
        'ranges',
        'James 1:2-3; Rom 12:1, 2, 3, 4; Jam 1:4; Roma 12:5',
        { ranges => [ { range => ['Romans 12:1-5; James 1:2-4'] } ] },
        'Romans 12:1-5; James 1:2-4',
    ],

    [
        'ranges with translations',
        'James 1:2-3 NIV NASB* Rom 12:1 NOTREALTRANSLATION ESV',
        {
            ranges => [ { range => ['Romans 12:1; James 1:2-3'] } ],
            bibles => {
                primary   => [ qw( ESV NIV ) ],
                auxiliary => ['NASB'],
            },
        },
        'Romans 12:1; James 1:2-3 ESV NASB* NIV',
    ],

    [
        'ranges with weights',
        'Jam 1:4; Roma 12:5 (20%) James 1:2-3; Rom 12:1, 2, 3, 4 (80%) Awesome Verses',
        {
            ranges => [
                {
                    range  => ['Romans 12:1-4; James 1:2-3'],
                    weight => 4,
                },
                {
                    range  => ['Romans 12:5; James 1:4'],
                    weight => 1,
                },
                {
                    range  => [ \'Awesome Verses' ],
                    weight => 1,
                },
            ],
            aliases => {
                'Awesome Verses' => 'Ephesians 6:10-17; Wisdom Verses',
            },
        },
        'Romans 12:1-4; James 1:2-3 (4) Romans 12:5; James 1:4 (1) Awesome Verses (1)',
    ],

    [
        'intersections and filters',
        'James 1 ~ James 1:2-4 | James 1:3 ~ Romans 12',
        {
            ranges        => [ { range => ['James 1'] } ],
            intersections => ['Romans 12; James 1:2-4'],
            filters       => ['James 1:3'],
        },
        'James 1 ~ Romans 12; James 1:2-4 | James 1:3',
    ],

    [
        'aliases',
        'Awesome Verses; Romans 12:1-2',
        {
            ranges  => [ { range => [
                'Romans 12:1-2',
                \'Awesome Verses',
            ] } ],
            aliases => {
                'Awesome Verses' => 'Ephesians 6:10-17; Wisdom Verses',
            },
        },
        'Romans 12:1-2; Awesome Verses',
    ],
) {
    is( $obj->parse( $_->[1] ), $_->[2], 'parse: ' . $_->[0] );
    is( $obj->canonicalize( $_->[1] ), $_->[3], 'canonicalize: ' . $_->[0] );
}

$obj->user_aliases([
    $obj->user_aliases->@*,
    {
        name  => 'Primes',
        label => 'Ephesians 6:1, 3, 5, 7, 11; Romans 12:1, 3, 5, 7, 11; James 1:1, 3, 5, 7, 11',
    },
    {
        name  => 'Awesome Verses Without Primes',
        label => 'Awesome Verses | Primes',
    },
]);

my $crazy_raw_input = join( ' ',
    'James 1:2-3; NIV NASB* Roma 12:5 (20%)',
    'Rom 12:1, 2, 3, 4; NOTREALTRANSLATION Jam 1:4-10; Rom 12:5-6 (80%)',
    'Stuff and Things and Awesome Verses Without Primes and Words To Ignore',
    '~ James 1:2-7 | James 1:3 ESV (1) ~ Romans 12 (5) | Wisdom Verses (15)',
);

my $crazy_canonicalized = join( ' ',
    'Romans 12:1-6; James 1:4-10 (4) Romans 12:5; James 1:2-3 (1) Awesome Verses Without Primes (1)',
    '~ Romans 12; James 1:2-7 | James 1:3; Wisdom Verses ESV NASB* NIV',
);

is(
    $obj->canonicalize($crazy_raw_input),
    $crazy_canonicalized,
    'crazy canonicalization',
);

$obj->user_aliases([
    $obj->user_aliases->@*,
    {
        name  => 'James Stuff',
        label => 'James 1:2-18 ~ James 1:5-25; Primes | James 1:13-15',
    },
    {
        name  => 'James Things',
        label => 'James 1:26; James Stuff',
    },
]);

is(
    $obj->descriptionize('James 1:27; James Things ~ James 1:5-11, 26-27 | James 1:11'),
    'James 1:5-10, 26-27',
    'descriptionize full feature simple',
);

is(
    $obj->descriptionize($crazy_canonicalized),
    'Romans 12:1-6; James 1:4 (4) Romans 12:5; James 1:2 (1) ESV NASB* NIV',
    'crazy descriptionize',
);

is(
    $obj->descriptionize($crazy_raw_input),
    'Romans 12:1-6; James 1:4 (4) Romans 12:5; James 1:2 (1) ESV NASB* NIV',
    'crazy descriptionize',
);

is(
    $obj->canonicalize('James 1:2 (1) (1)'),
    'James 1:2',
    'simplification canonicalization',
);

$obj->user_aliases([
    {
        name  => 'Alias',
        label => 'Luke John',
    },
]);

# - If both the parent and child labels lack weights,
#   replace the child label name with its contents
#     - Alias: `Luke John`
#     - Parent Label: `Alias; Acts; Jude`
#     - Description: `Luke; John; Acts; Jude`

is(
    $obj->descriptionize('Alias; Acts; Jude'),
    'Luke; John; Acts; Jude',
    'both parent and alias without weights',
);

# - If the parent has weights but the child label lacks weights,
#   replace the child label name with its contents
#     - Alias: `Luke John`
#     - Parent Label: `Alias (1) Acts (2) Jude (3)`
#     - Description: `Luke; John (1) Acts (2) Jude (3)`

is(
    $obj->descriptionize('Alias (1) Acts (2) Jude (3)'),
    'Luke; John (1) Acts (2) Jude (3)',
    'parent with weights alias without weights',
);

$obj->user_aliases([
    {
        name  => 'Alias',
        label => 'Luke (1) John (3)',
    },
]);

# - If both the parent and child labels have weights,
#   and the label is the only reference in its range,
#   proportionally cascade the child label weights
#     - Alias: `Luke (1) John (3)`
#     - Parent Label: `Alias (1) Acts (1)`
#     - Mental Model: `{ Luke (1) John (3) } (1) Acts (1)`
#     - Description: `Luke (1) John (3) Acts (4)`

is(
    $obj->descriptionize('Alias (1) Acts (1)'),
    'Luke (1) John (3) Acts (4)',
    'both the parent and child labels have weights; solo label reference',
);

# - If both the parent and child labels have weights,
#   but the label is not the only reference in its range,
#   drop the child weights
#     - Alias: `Luke (1) John (3)`
#     - Parent Label: `Alias; Acts (1) Jude (1)`
#     - Description: `Luke; John; Acts (1) Jude (1)`

is(
    $obj->descriptionize('Alias; Acts (1) Jude (1)'),
    'Luke; John; Acts (1) Jude (1)',
    'both the parent and child labels have weights; not solo label reference',
);

# - If the parent label lacks weights but the child label has weights,
#   drop the child weights
#     - Alias: `Luke (1) John (3)`
#     - Parent Label: `Alias; Acts`
#     - Description: `Luke; John; Acts`

is(
    $obj->descriptionize('Alias; Acts'),
    'Luke; John; Acts',
    'parent without weights and child with weights',
);

is(
    $obj->canonicalize('1 Corinthians 16:15-16 (1) 1 Corinthians 16:15-16, 19, 22-24 (1) NIV +2 Verses'),
    '1 Corinthians 16:15-18 (1) 1 Corinthians 16:15-24 (1) NIV',
    'add verses suffix +2',
);

is(
    $obj->canonicalize('1 Corinthians 15:57 (1) 1 Corinthians 15:57 (1) NIV + 400ver'),
    '1 Corinthians 15:57-58; 16 (1) 1 Corinthians 15:57-58; 16 (1) NIV',
    'add verses suffix +400',
);

done_testing;
