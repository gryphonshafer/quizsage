use Test2::V0;
use exact -conf;
use Omniframe::Test::App;
use QuizSage::Model::Meet;
use QuizSage::Model::Quiz;
use QuizSage::Test;

setup;

my ($user) = user;

my $qm_auth   = 0;
my $mock_user = mock $user => ( override => [ qm_auth => sub { $qm_auth } ] );

my $quiz_settings = undef;
my $mock_meet     = mock 'QuizSage::Model::Meet' => ( override => [
    new           => sub { $_[0] },
    load          => sub { $_[0] },
    id            => sub { 42 },
    quiz_settings => sub { $quiz_settings },
    data          => sub { {} },
] );

my $mock_quiz = mock 'QuizSage::Model::Quiz' => ( override => [
    new                => sub { $_[0] },
    every_data         => sub { [] },
    create             => sub { $_[0] },
    id                 => sub { 42 },
    distribution_check => sub {},
] );

mojo->app->hook( before_routes => sub ($c) { $c->session( user_id => $user->id ) } );

mojo->post_ok( '/quiz/build', form => { meet => 42 } )
    ->status_is(302)
    ->header_is( location => url('/meet/42') );

$qm_auth = 1;

mojo->post_ok( '/quiz/build', form => { meet => 42 } )
    ->status_is(302)
    ->header_is( location => url('/meet/42') );

$quiz_settings = {};

mojo->post_ok(
    '/quiz/build',
    form => {
        meet => 42,
        team => [ 'Team 1', 'Team 2', 'Team 3' ],
    },
)
    ->status_is(302)
    ->header_is( location => url('/quiz/42') );

teardown;
