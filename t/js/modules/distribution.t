use Test2::V0;
use exact -conf;
use Omniframe::Class::Javascript;

my $distribution = Omniframe::Class::Javascript->new(
    basepath  => conf->get( qw( config_app root_dir ) ) . '/static/js',
    importmap => {
        'modules/distribution' => 'modules/distribution',
    },
)->run(
    q{
        import distribution from 'modules/distribution';

        OCJS.out(
            distribution(
                OCJS.in.types,
                OCJS.in.bibles,
                OCJS.in.teams_count,
            )
        );
    },
    {
        bibles      => [ qw( NIV NASB ) ],
        teams_count => 3,
        types       => {
            p => { fresh_bible => 1 },
            c => { fresh_bible => 1 },
            q => { fresh_bible => 0 },
            f => { fresh_bible => 1 },
        },
    },
)->[0][0];

is( scalar(@$distribution), 12, '12 primary queries for 3 teams' );

my $bible_count = grep { $_->{bible} and $_->{bible} eq 'NIV' } @$distribution;
ok(
    $bible_count == 4 || $bible_count == 5,
    '~50% of non-Q queries are NIV',
);

is( scalar( grep { $_->{type} eq 'Q' } @$distribution ), 3, '25% of queries are Q' );

my @bibles = grep { defined } map { $_->{bible} } @$distribution;
isnt( $bibles[0], $bibles[1], 'bibles rotate' );

done_testing;
