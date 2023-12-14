use Test2::V0;
use exact -conf;
use QuizSage::Model::Quiz;

my $obj;
ok( lives { $obj = QuizSage::Model::Quiz->new }, 'new' ) or note $@;
DOES_ok( $obj, 'Omniframe::Role::Model' );
# can_ok( $obj, 'active_quizzes' );

done_testing;
