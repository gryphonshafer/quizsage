use Test2::V0;
use exact -conf;
use Omniframe::Util::File 'opath';
use QuizSage::Model::Label;

my $obj;
ok( lives { $obj = QuizSage::Model::Label->new }, 'new' ) or note $@;
DOES_ok( $obj, $_ ) for ( qw(
    Omniframe::Role::Model
    QuizSage::Role::Label::Bible
    QuizSage::Role::Label::Description
    QuizSage::Role::Label::Parse
) );
can_ok( $obj, qw(
    user_id user_aliases
    aliases identify_aliases format canonicalize descriptionize fabricate
    bible_ref bible_structure bibles bible_acronyms
    canonicalize_refs versify_refs
    descriptionate
    parse
) );
ref_ok( $obj->aliases, 'ARRAY', 'aliases returns arrayref' );
ref_ok( $obj->bible_acronyms, 'ARRAY', 'bible_acronyms returns arrayref' );

my $test_data = YAML::XS::Load( opath('t/data/labels.yaml')->slurp );

$obj->bible_acronyms( [ qw( ESV NASB NIV NIV84 ) ] );
$obj->user_id(1);
$obj->user_aliases( $test_data->{aliases} );

for my $case_set ( $test_data->{cases}->@* ) {
    my ($case_set_name) = keys %$case_set;
    for my $case ( $case_set->{$case_set_name}->@* ) {
        my $case_title = sprintf( '%s - %s ', $case_set_name, $case->{name} );

        my $parse = $obj->parse( $case->{input} );
        is( $parse, $case->{parse}, 'parse: ' . $case_title );
        is( $obj->format($parse), $case->{canonical}, 'format: ' . $case_title );

        my @description = $obj->descriptionize( $case->{input} );
        is( $description[0], $case->{description}, 'description: ' . $case_title );
    }
}

is( $obj->is_multi_chapter( $_->[1] ), $_->[0], 'is_multi_chapter: ' . $_->[1] ) for (
    [ 0, '1 Cor 1'                          ],
    [ 1, '1 Cor 1-3'                        ],
    [ 1, '1 Cor 1 (1) 1 Cor 3 (1)'          ],
    [ 0, '1 Cor 1:1-5 (1) 1 Cor 1:6-10 (1)' ],
);

done_testing;
