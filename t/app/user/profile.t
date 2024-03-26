use Test2::V0;
use exact -conf;
use Omniframe::Test::App;
use QuizSage::Model::User;

setup;

my $email  = stuff('email');
my $passwd = 'terrible_but_long_enough_password';

my $user = QuizSage::Model::User->new->create({
    email      => $email,
    passwd     => $passwd,
    first_name => 'First Name',
    last_name  => 'Last Name',
    phone      => '1234567890',
});
$user->save({ active => 1 });

mojo->app->hook( before_routes => sub ($c) { $c->session( captcha => 1234567 ) } );

mojo->post_ok(
        '/user/login',
        form => {
            email  => $email,
            passwd => $passwd,
        },
    )
    ->status_is(302)
    ->header_is( location => url('/') )
    ->get_ok('/')
    ->status_is(200)
    ->attr_is( 'dialog#message', 'class', 'error' )
    ->text_like( 'dialog#message', qr|captcha sequence provided does not match| );

mojo->post_ok(
        '/user/login',
        form => {
            email   => $email,
            passwd  => $passwd,
            captcha => 1234567,
        },
    )
    ->status_is(302)
    ->header_is( location => url('/') )
    ->get_ok('/')
    ->status_is(200)
    ->content_like( qr|Logged in as: <b>First Name</b>| );

mojo->get_ok('/user/profile')->status_is(200);

mojo->post_ok(
        '/user/profile',
        form => {
            email      => 'new_' . $email,
            passwd     => 'new_' . $passwd,
            first_name => 'New First Name',
            last_name  => 'New Last Name',
            phone      => '4567891230',
            captcha    => 1234567,
        },
    )
    ->status_is(302)
    ->header_is( location => url('/') )
    ->get_ok('/')
    ->status_is(200)
    ->attr_is( 'dialog#message', 'class', 'success' )
    ->text_like( 'dialog#message', qr|Successfully edited user profile| );

is(
    stuff('dq')->get(
        'user',
        [ qw( email first_name last_name phone ) ],
        { email => '?' },
    )->run( 'new_' . $email )->all({}),
    [{
        email      => 'new_' . $email,
        first_name => 'New First Name',
        last_name  => 'New Last Name',
        phone      => '4567891230',
    }],
    'user profile new data correct',
);

mojo->post_ok(
        '/user/profile' => form => {
            passwd  => 'short',
            captcha => 1234567,
        },
    )
    ->status_is(200)
    ->attr_is( 'dialog#message', 'class', 'error' );

teardown;
