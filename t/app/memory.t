use Test2::V0;
use exact -conf;
use Omniframe::Test::App;

setup;

my $user = QuizSage::Model::User->new->create({
    email      => stuff('email'),
    passwd     => 'terrible_but_long_enough_password',
    first_name => 'First Name',
    last_name  => 'Last Name',
    phone      => '1234567890',
});
$user->save({ active => 1 });

mojo->get_ok($_)
    ->status_is(302)
    ->header_is( location => url('/') )
    ->get_ok('/')
    ->status_is(200)
    ->attr_is( 'dialog#message', 'class', 'error' )
    ->text_like( 'dialog#message', qr|Login required for the previously requested resource| )
    for (
        '/memory/memorize',
        '/memory/review',
        '/memory/state',
    );

mojo->app->hook( before_routes => sub ($c) { $c->session( user_id => $user->id ) } );

mojo->get_ok('/memory/memorize')
    ->status_is(200)
    ->text_is( title => 'QuizSage: Initial Memorization' );

mojo->get_ok('/memory/review')
    ->status_is(200)
    ->text_is( title => 'QuizSage: Memorization Review' );

mojo->get_ok('/memory/state')
    ->status_is(200)
    ->text_is( title => 'QuizSage: Memory State' );

teardown;
