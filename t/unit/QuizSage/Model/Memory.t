use Test2::V0;
use exact -conf;
use QuizSage::Model::Memory;

my $obj;
ok( lives { $obj = QuizSage::Model::Memory->new }, 'new' ) or note $@;
DOES_ok( $obj, 'Omniframe::Role::Model' );
can_ok( $obj, qw(
    to_memorize
    memorized
) );

done_testing;
