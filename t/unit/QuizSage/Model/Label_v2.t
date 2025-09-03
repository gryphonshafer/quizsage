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

for ( $test_data->{cases}->@* ) {
    my $parse = $obj->__parse( $_->{input} );
    # warn YAML::XS::Dump($parse) . "\n";
    is( $parse, $_->{parse}, 'Parse: ' . $_->{input} );
    # is( $obj->__canonicalize($parse), $_->{canonical}, 'Canonical: ' . $_->{canonical} );
}

done_testing;
