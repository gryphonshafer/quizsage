use Test2::V0;
use exact -conf;
use QuizSage::Model::User;

my $obj;
ok( lives { $obj = QuizSage::Model::User->new }, 'new' ) or note $@;
DOES_ok( $obj, "Omniframe::Role::$_" ) for ( qw( Model Bcrypt ) );
can_ok( $obj, qw( validate freeze thaw send_email login ) );

done_testing;
