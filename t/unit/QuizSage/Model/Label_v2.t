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

for my $case_set ( $test_data->{cases}->@* ) {
    my ($case_set_name) = keys %$case_set;

    for my $case ( $case_set->{$case_set_name}->@* ) {
        # next unless ( $case->{name} eq 'filter' );

        my $parse = $obj->__parse( $case->{input} );

        # warn YAML::XS::Dump($parse) . "\n";
        # p $parse;

        is(
            $parse,
            $case->{parse},
            'Parse: ' .
                ucfirst($case_set_name) . ' - ' .
                ucfirst( $case->{name} ) . ' = "' . $case->{input} . '"',
        );

        $obj->__format($parse);
    }
}

done_testing;
