use Test2::V0;
use exact -conf;
use Omniframe;
use QuizSage::Model::Season;
use QuizSage::Model::Meet;

my $obj;

ok(
    lives { $obj = Omniframe->with_roles('QuizSage::Role::Meet::Settings')->new },
    q{with_roles('QuizSage::Role::Meet::Settings')->new},
) or note $@;

DOES_ok( $obj, $_ ) for ( qw(
    Omniframe::Role::Model
    QuizSage::Role::Meet::Settings
) );

can_ok( $obj, $_ ) for ( qw(
    merged_settings
    build_settings
    canonical_settings
    thaw_roster_data
    freeze_roster_data
) );

$obj->dq('material')->begin_work;

my $sth = $obj->dq('material')->sql(q{
    INSERT INTO bible (acronym) VALUES (?)
    ON CONFLICT(acronym) DO NOTHING
});

$sth->run($_) for ( qw( BSB ESV NIV NASB NASB5 ) );

my $roster_data = {
    default_bible => 'NIV',
    tags          => {
        default => ['Veteran'],
        append  => ['Youth'],
    },
    data => join( "\n",
        'Team 1',
        'Alpha Bravo',
        'Charlie Delta',
        'Echo Foxtrox',
        '',
        'Team 2 NASB5',
        'Gulf Hotel',
        'Juliet India NASB (Rookie)',
        'Kilo Lima (Rookie)',
        '',
        'Team 3',
        'Mike November',
        'Oscar Papa (Rookie)',
        'Romeo Quebec',
    ),
};

my $roster;
ok(
    lives {
        $roster = $obj->thaw_roster_data(
            $roster_data->{data},
            $roster_data->{default_bible},
            $roster_data->{tags},
        )->{roster};
    },
    'thaw_roster_data',
) or note $@;

ref_ok( $roster, 'ARRAY', 'roster data is an arrayref' );
is(
    $roster->[1],
    {
        name     => 'Team 2',
        quizzers => [
            {
                bible => 'NASB5',
                name  => 'Gulf Hotel',
                tags  => [ 'Veteran', 'Youth' ],
            },
            {
                bible => 'NASB',
                name  => 'Juliet India',
                tags  => [ 'Rookie', 'Youth' ],
            },
            {
                bible => 'NASB5',
                name  => 'Kilo Lima',
                tags  => [ 'Rookie', 'Youth' ],
            },
        ],
    },
    'team 2 data',
);

my $frozen_roster_data;
ok(
    lives {
        $frozen_roster_data = $obj->freeze_roster_data(
            $roster,
            $roster_data->{default_bible},
            $roster_data->{tags},
        );
    },
    'freeze_roster_data',
) or note $@;

is(
    $frozen_roster_data,
    join( "\n",
        'Team 1',
        'Alpha Bravo',
        'Charlie Delta',
        'Echo Foxtrox',
        '',
        'Team 2',
        'Gulf Hotel NASB5',
        'Juliet India NASB (Rookie)',
        'Kilo Lima NASB5 (Rookie)',
        '',
        'Team 3',
        'Mike November',
        'Oscar Papa (Rookie)',
        'Romeo Quebec',
    ),
    'freeze_roster_data data',
);

my $meet = QuizSage::Model::Meet->new;
$meet->dq->begin_work;

my $season = QuizSage::Model::Season->new->create({
    name     => 'Name',
    location => 'Location',
    start    => time - 60 * 60 * 24 * 365.25 * 7,
});

$meet->create({
    season_id => $season->id,
    name     => 'Name',
    location => 'Location',
    start    => time - 60 * 60 * 24 * 365.25 * 7,
    passwd   => 'password',
});

my $canonical_settings = $meet->canonical_settings;

is(
    $canonical_settings,
    hash {
        field brackets => array {
            all_items hash {
                field name     => T();
                field material => T();
                field rooms    => T();
                field weight   => T();
                etc();
            };
            etc();
        };
        roster   => { data => T() },
        schedule => T(),
        etc();
    },
    'canonical_settings',
);

$meet->dq->rollback;
$obj->dq('material')->rollback;

done_testing;
