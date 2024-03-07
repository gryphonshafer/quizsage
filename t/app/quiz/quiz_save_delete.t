use Test2::V0;
use exact -conf;
use Omniframe::Test::App;
use QuizSage::Model::Quiz;
use QuizSage::Model::User;

setup;

my $user = QuizSage::Model::User->new->create({
    email      => stuff('email'),
    passwd     => 'terrible_but_long_enough_password',
    first_name => 'First Name',
    last_name  => 'Last Name',
    phone      => '1234567890',
});
$user->save({ active => 1 });

my $meet_id   = 0;
my $mock_quiz = mock 'QuizSage::Model::Quiz' => ( override => [
    new                         => sub { $_[0] },
    load                        => sub { $_[0] },
    ensure_material_json_exists => 1,
    data                        => sub { +{ meet_id => $meet_id } },
    save                        => 1,
] );

mojo->app->hook( before_routes => sub ($c) { $c->session( user_id => $user->id ) } );

mojo->get_ok('/quiz/42')
    ->status_is(200)
    ->element_exists('div#quiz');

mojo->get_ok('/quiz/42.json')
    ->status_is(200)
    ->json_has('/json_material_path');

mojo->post_ok('/quiz/save/42')
    ->status_is(200)
    ->json_is( '/quiz_data_saved', 0 );

$meet_id = 42;

mojo->get_ok('/quiz/delete/42')
    ->status_is(302)
    ->header_is( location => url('/meet/42') );

teardown;
