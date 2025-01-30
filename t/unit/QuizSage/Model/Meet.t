use Test2::V0;
use exact -conf;
use QuizSage::Model::Meet;
use QuizSage::Model::Season;

my $obj;
ok( lives { $obj = QuizSage::Model::Meet->new }, 'new' ) or note $@;
DOES_ok( $obj, $_ ) for ( qw(
    Omniframe::Role::Model
    QuizSage::Role::Meet::Build
    QuizSage::Role::Meet::Settings
    QuizSage::Role::Meet::Editing
) );
can_ok( $obj, qw(
    create
    freeze thaw
    from_season_meet
    state
    quiz_settings
    stats
) );

$obj->dq->begin_work;

ok(
    lives {
        my $season = QuizSage::Model::Season->new->create({
            name     => 'Name',
            location => 'Location',
            start    => time - 60 * 60 * 24 * 365.25 * 7,
        });
        $obj->create({
            season_id => $season->id,
            name     => 'Name',
            location => 'Location',
            start    => time - 60 * 60 * 24 * 365.25 * 7,
            passwd   => 'password',
        });
    },
    q/create(...)/,
) or note $@;

ok( lives { $obj->state }, 'state' ) or note $@;
ok( lives { $obj->quiz_settings( 'bracket', 'quiz') }, 'quiz_settings' ) or note $@;
ok( lives { $obj->stats }, 'stats' ) or note $@;

$obj->dq->rollback;

done_testing;
