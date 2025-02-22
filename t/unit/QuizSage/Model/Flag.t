use Test2::V0;
use exact -conf;
use Mojo::URL;
use QuizSage::Model::Flag;

my $obj;
ok( lives { $obj = QuizSage::Model::Flag->new }, 'new' ) or note $@;
DOES_ok( $obj, 'Omniframe::Role::Model' );
can_ok( $obj, qw( freeze thaw list ) );

done_testing;
