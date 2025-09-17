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

my $cases;
for my $case_set ( $test_data->{cases}->@* ) {
    my ($case_set_name) = keys %$case_set;
    for my $case ( $case_set->{$case_set_name}->@* ) {
        $cases->{ $case->{name} } = {
            case_set_name => $case_set_name,
            case          => $case,
        };
    }
}

for my $case_name (
    'references',
    'references with bibles',
    'weights',
    'filter',
    'intersection',
    'addition',
    'block with filter',
    'alias',
    'alias with nested alias',
    'aliases with confusing syntax',
    'alias inside intersection',

    # 'distributive with aliases and special',

    'lowest common denominator weights',
    'text node after weighted blocks',
    'block node after weighted blocks',
    'remove weight if only 1 set',
    'block that doesn\'t need to be a block',
    'block that wraps only a single block',
    'merge single scope intersections/filters',
    'intersection with weight',
    'addition in a weight',

    # 'block with addition',

    'unweighted set with unnecessary block',

    # 'nested block with filter',
    # 'block with distributive',
    # 'block with nested distributive',

    'intersection followed by addition',
) {
    my $case          = $cases->{$case_name}{case};
    my $case_set_name = $cases->{$case_name}{case_set_name};

    my $parse = $obj->__parse( $case->{input} );

    warn YAML::XS::Dump($parse) . "\n" if 0;
    p $parse if 0;

    my $case_title = sprintf( '%-10s - %-40s ', $case_set_name, $case->{name} );

    is( $parse, $case->{parse}, 'parse:       ' . $case_title . '< ' . $case->{input} );
    is( $obj->__format($parse), $case->{canonical}, 'format:      ' . $case_title . '> ' . $case->{canonical} );

    my @description = $obj->__descriptionize( $case->{input} );

    is( $description[0], $case->{description}, 'description: ' . $case_title . '> ' . $case->{description} );

    $obj->warn( {
        in => {
            input => $case->{input},
            parse => $case->{parse},
        },
        out => {
            canonical   => $case->{canonical},
            description => $description[0],
            structure   => $description[1],
        },
    } ) if 0;

    <STDIN> if 0;
}

done_testing;
