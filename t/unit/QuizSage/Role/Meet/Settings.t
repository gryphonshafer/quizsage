use Test2::V0;
use exact -conf;
use Omniframe;

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

$sth->run($_) for ( qw( NIV NASB NASB5 ) );

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

ok(
    lives {
        $roster_data = $obj->thaw_roster_data(
            $roster_data->{data},
            $roster_data->{default_bible},
            $roster_data->{tags},
        )->{roster};
    },
    'thaw_roster_data',
) or note $@;

ref_ok( $roster_data, 'ARRAY', 'roster data is an arrayref' );
is(
    $roster_data->[1],
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

$obj->dq('material')->rollback;

done_testing;
