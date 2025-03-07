use Test2::V0;
use exact -conf;
use Omniframe::Test::App;
use QuizSage::Model::Meet;
use QuizSage::Model::Season;
use QuizSage::Model::Quiz;
use QuizSage::Test;

setup;

my ($user) = user;
mojo->app->hook( before_routes => sub ($c) { $c->session( user_id => $user->id ) } );

( my $name = lc( crypt( $$ . ( time + rand ), 'gs' ) ) ) =~ s/[^a-z0-9]+//g;
my $meet = QuizSage::Model::Meet->new->create({
    season_id => QuizSage::Model::Season->new->create({ name => 'Season ' . $name })->id,
    name      => 'Meet ' . $name,
    passwd    => 'test_meet_passwd',
});

my $quiz = QuizSage::Model::Quiz->new->create({
    meet_id  => $meet->id,
    user_id  => $user->id,
    bracket  => 'Test Bracket',
    name     => 'Test Quiz',
    settings => { room => 237 },
    state    => { thx => 1138 },
});

mojo->websocket_ok( '/meet/' . $meet->id . '/board/237' );

$quiz->data->{state}{thx}++;
$quiz->save;

mojo->message_ok;

is( mojo->message, [ text => '{"thx":1139}' ], 'message' );

teardown;
