use Test2::V0;
use exact -conf;
use Omniframe::Test::App;
use QuizSage::Model::User;
use QuizSage::Model::Season;

setup;

my $user = QuizSage::Model::User->new->create({
    email      => stuff('email'),
    passwd     => 'terrible_but_long_enough_password',
    first_name => 'First Name',
    last_name  => 'Last Name',
    phone      => '1234567890',
});
$user->save({ active => 1 });

my $season = QuizSage::Model::Season->new->create({ name => 'Season Test' });

mojo->get_ok( '/season/' . $season->id . '/stats' )
    ->status_is(302)
    ->header_is( location => url('/') )
    ->get_ok('/')
    ->status_is(200)
    ->attr_is( 'dialog#message', 'class', 'error' )
    ->text_like( 'dialog#message', qr|Login required for the previously requested resource| );

mojo->app->hook( before_routes => sub ($c) { $c->session( user_id => $user->id ) } );

mojo->get_ok( '/season/' . $season->id . '/stats' )
    ->status_is(200)
    ->text_is( 'h2:nth-of-type(1)', 'Quizzers by Points Average' )
    ->text_is( 'h2:nth-of-type(2)', 'Rookie Quizzers by Points Average' )
    ->text_is( 'h2:nth-of-type(3)', 'Quizzers with VRAs' );

teardown;
