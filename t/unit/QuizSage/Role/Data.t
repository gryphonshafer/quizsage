use Test2::V0;
use exact -conf;
use Omniframe;

my $obj;

ok(
    lives { $obj = Omniframe->with_roles('QuizSage::Role::Data')->new },
    q{with_roles('QuizSage::Role::Data')->new},
) or note $@;

DOES_ok( $obj, 'QuizSage::Role::Data' );
can_ok( $obj, qw( deepcopy dataload ) );

my $data_0    = { thx => 1138, answer => 42 };
my $data_1    = { data => $data_0 };
my $data_copy = [
    {
        thx    => 1138,
        answer => 42,
    },
    {
        data => {
            answer => 42,
            thx    => 1138,
        },
    },
];

my ( $deepcopy, @deepcopy );

ok( lives { $deepcopy = $obj->deepcopy( $data_0, $data_1 ) }, 'deepcopy to scalar' ) or note $@;
ok( lives { @deepcopy = $obj->deepcopy( $data_0, $data_1 ) }, 'deepcopy to array'  ) or note $@;

is ( $deepcopy,  $data_copy, 'deepcopy to scalar data check' );
is ( \@deepcopy, $data_copy, 'deepcopy to array data check'  );

ref_ok( $obj->dataload('config/meets/defaults/season.yaml'), 'HASH', 'season YAML data decoded' );

done_testing;
