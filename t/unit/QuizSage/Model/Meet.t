use Test2::V0;
use exact -conf;
use QuizSage::Model::Meet;
use QuizSage::Model::Season;
use QuizSage::Model::User;

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
$obj->dq('material')->begin_work;

my $sth = $obj->dq('material')->sql(q{
    INSERT INTO bible (acronym) VALUES (?)
    ON CONFLICT(acronym) DO NOTHING
});

$sth->run($_) for ( qw( NIV NASB NASB5 ) );

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
        })->build;
    },
    q/create(...)/,
) or note $@;

is(
    QuizSage::Model::Meet->new->from_season_meet( 'Name', 'Name' )->id,
    $obj->id,
    'from_season_meet',
);

$obj->data->{build}{brackets}[-1]{finals} = 'first_to_win_twice';
for my $bracket ( $obj->data->{build}{brackets}->@* ) {
    for my $quiz ( map { $_->{rooms}->@* } $bracket->{sets}->@* ) {
        QuizSage::Model::Quiz->new->create({
            meet_id  => $obj->id,
            bracket  => $bracket->{name},
            name     => $quiz->{name},
            settings => $obj->quiz_settings( $bracket->{name}, $quiz->{name} ),
            state    => {
                board => [ {} ],
                teams => [ {
                    name     => 'Team',
                    quizzers => [],
                    score    => {
                        position => 1,
                        points   => 1,
                        bonuses  => 1,
                    },
                } ],
            },
        });
    }
}

ok( lives { $obj->state }, 'state' ) or note $@;
ok( lives { $obj->quiz_settings( 'bracket', 'quiz' ) }, 'quiz_settings' ) or note $@;
ok( lives { $obj->stats }, 'stats' ) or note $@;

my $user = QuizSage::Model::User->new->create({
    email      => 'example@example.com',
    passwd     => 'terrible_but_long_password',
    first_name => 'first_name',
    last_name  => 'last_name',
    phone      => '1234567890',
});

is( $obj->admin_auth($user), 0, 'admin_auth 0' );
ok( lives { $obj->admin( 'add', $user->id ) }, 'admin' ) or note $@;
is( $obj->admin_auth($user), 1, 'admin_auth 1' );
is( $obj->admins, [{
    email      => 'example@example.com',
    first_name => 'first_name',
    last_name  => 'last_name',
    user_id    => T(),
}], 'admins' );

$obj->dq->rollback;
$obj->dq('material')->rollback;

done_testing;
