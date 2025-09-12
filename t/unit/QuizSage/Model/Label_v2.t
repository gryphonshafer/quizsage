use Test2::V0;
use exact -conf;
use Omniframe::Util::File 'opath';
use QuizSage::Model::Label;
use YAML::XS;
use DDP;

my $test_data = YAML::XS::Load( opath('t/data/labels.yaml')->slurp );

my $obj;
ok( lives { $obj = QuizSage::Model::Label->new }, 'new' ) or note $@;

$obj->bible_acronyms( [ qw( ESV NASB NIV NIV84 ) ] );
$obj->user_id(1);
$obj->user_aliases( $test_data->{aliases} );

ok( 1, 1 );
my $count;

for my $case_set ( $test_data->{cases}->@* ) {
    my ($case_set_name) = keys %$case_set;

    for my $case ( $case_set->{$case_set_name}->@* ) {
        next unless ( grep { $case->{name} eq $_ }
            'references with bibles',
            'weights',
            'filter',
            'addition',
            'block with filter',
            'alias with nested alias',
            'distributive with aliases and special',
        );
        # next unless ( ++$count <= 4 );

        my $parse = $obj->__parse( $case->{input} );

        # warn YAML::XS::Dump($parse) . "\n";
        # p $parse;

        my $case_title = sprintf( '%-10s - %-40s ',
            ucfirst($case_set_name),
            ucfirst( $case->{name} ),
        );

        is( $parse, $case->{parse}, 'Parse:  ' . $case_title . '< ' . $case->{input} );
        is( $obj->__format($parse), $case->{canonical}, 'Format: ' . $case_title . '> ' . $case->{canonical} );

        $obj->warn( '>>>>>>>>>>>>>>', $case->{canonical} );
        $obj->warn( '<<<<<<<<<<<<<<', $obj->__descriptionize( $case->{input} ) );
    }
}

done_testing;
