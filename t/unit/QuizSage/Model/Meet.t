use Test2::V0;
use exact -conf;
use QuizSage::Model::Meet;

my $obj;
ok( lives { $obj = QuizSage::Model::Meet->new }, 'new' ) or note $@;
DOES_ok( $obj, $_ ) for ( qw(
    Omniframe::Role::Bcrypt
    Omniframe::Role::Model
    Omniframe::Role::Time
    QuizSage::Role::Meet::Build
    QuizSage::Role::Data
) );
can_ok( $obj, qw(
    create
    freeze thaw
    state
    quiz_settings
    stats
) );

ok( lives { $obj->state }, 'state' ) or note $@;
ok( lives { $obj->quiz_settings( 'bracket', 'quiz') }, 'quiz_settings' ) or note $@;
ok( lives { $obj->stats }, 'stats' ) or note $@;

done_testing;
