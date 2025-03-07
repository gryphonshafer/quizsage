use Test2::V0;
use exact -conf;
use QuizSage::Model::Memory;
use QuizSage::Test;

my $obj;
ok( lives { $obj = QuizSage::Model::Memory->new }, 'new' ) or note $@;
DOES_ok( $obj, 'Omniframe::Role::Model' );
can_ok( $obj, qw(
    bible_ref
    to_memorize
    memorized
    review_verse
    reviewed
    state
    tiles
    report
    sharing
) );

$obj->dq->begin_work;

my ($user) = user;

ok( lives {
    $obj->memorized({
        user_id => $user->id,
        book    => 'James',
        chapter => 1,
        verse   => 5,
        bible   => 'NIV',
        level   => 10,
    });
}, 'memorized' ) or note $@;

my $memory_id = $obj->dq->last_insert_id;

ok( lives { $obj->reviewed( $memory_id, 9, $user->id ) }, 'reviewed' ) or note $@;

my ($other_user) = user;

ok( lives { $obj->sharing({
    action            => 'add',
    memorizer_user_id => $user->id,
    shared_user_id    => $other_user->id,
}) }, 'sharing add' ) or note $@;

ok( lives { $obj->sharing({
    action            => 'remove',
    memorizer_user_id => $user->id,
    shared_user_id    => $other_user->id,
}) }, 'sharing remove' ) or note $@;

$obj->dq->rollback;

done_testing;
