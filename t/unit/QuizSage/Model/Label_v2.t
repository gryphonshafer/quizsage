use Test2::V0;
use exact -conf;
use Omniframe::Util::File 'opath';
use QuizSage::Model::Label;
use YAML::XS;

my $test_data = YAML::XS::Load( opath('t/data/labels.yaml')->slurp );

my $obj;
ok( lives { $obj = QuizSage::Model::Label->new }, 'new' ) or note $@;

$obj->bible_acronyms( [ qw( ESV NASB NIV NIV84 ) ] );
$obj->user_id(1);
$obj->user_aliases( $test_data->{aliases} );

for my $case_set_name ( sort keys $test_data->{cases}->%* ) {
    for my $case ( $test_data->{cases}{$case_set_name}->@* ) {
        my $parse = $obj->__parse( $case->{input} );
        # warn YAML::XS::Dump($parse) . "\n";
        is(
            $parse,
            $case->{parse},
            'Parse: ' .
                ucfirst($case_set_name) . ' - ' .
                ucfirst( $case->{name} ) . ' = "' . $case->{input} . '"',
        );
    }
}

done_testing;
