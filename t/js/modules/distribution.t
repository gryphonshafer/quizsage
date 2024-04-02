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
        types       => [ qw( P C Q F ) ],
        bibles      => [ qw( NIV NASB ) ],
        teams_count => 3,
    },
)->[0][0];

is( scalar(@$distribution), 12, '12 primary queries for 3 teams' );
is( scalar( grep { $_->{bible} eq 'NIV' } @$distribution ), 6, '50% of queries are NIV' );
is( scalar( grep { $_->{type} eq 'Q' } @$distribution ), 3, '25% of queries are Q' );
isnt( $distribution->[0]{bible}, $distribution->[1]{bible}, 'bibles rotate' );

done_testing;
