use Test2::V0;
use exact -conf;
use Omniframe::Test::App;

setup;

mojo->get_ok('/user/create')
    ->status_is(200)
    ->attr_is( 'form', 'method', 'post' );

my $email  = stuff('email');
my $passwd = 'terrible_but_long_enough_password';

mojo->app->hook( before_routes => sub ($c) { $c->session( captcha => 1234567 ) } );

mojo->post_ok(
        '/user/create',
        form => {
            email      => $email,
            passwd     => $passwd,
            first_name => 'First Name',
            last_name  => 'Last Name',
            phone      => '1234567890',
        },
    )
    ->status_is(200)
    ->attr_is( 'dialog#message', 'class', 'error' )
    ->text_like( 'dialog#message', qr|captcha sequence provided does not match| );

mojo->post_ok(
        '/user/create',
        form => {
            email      => $email,
            passwd     => $passwd,
            first_name => 'First Name',
            last_name  => 'Last Name',
            phone      => '123',
            captcha    => 1234567,
        },
    )
    ->status_is(200)
    ->attr_is( 'dialog#message', 'class', 'error' )
    ->text_like( 'dialog#message', qr|Phone supplied is not at least 10 digits in length| );

mojo->post_ok(
        '/user/create',
        form => {
            email      => $email,
            passwd     => $passwd,
            first_name => 'First Name',
            last_name  => 'Last Name',
            phone      => '1234567890',
            captcha    => 1234567,
        },
    )
    ->status_is(302)
    ->header_is( location => url('/') )
    ->get_ok('/')
    ->status_is(200)
    ->attr_is( 'dialog#message', 'class', 'success' )
    ->text_like( 'dialog#message', qr|Successfully created user| );

my $user = stuff('dq')
    ->get( 'user', [ qw( user_id passwd phone active ) ], { email => '?' } )
    ->run($email)
    ->first({});

is(
    $user,
    {
        user_id => D(),
        passwd  => D(),
        phone   => '1234567890',
        active  => 0,
    },
    'user ID, phone, and active ok',
);

mojo->post_ok( '/user/verify/' . $user->{user_id} . '/a1b2c3' )
    ->status_is(302)
    ->header_is( location => url('/') )
    ->get_ok('/')
    ->status_is(200)
    ->attr_is( 'dialog#message', 'class', 'error' )
    ->text_like( 'dialog#message', qr|Unable to verify| );

is(
    stuff('dq')->get( 'user', ['active'], { email => '?' } )->run($email)->value,
    0,
    'user not verified (yet)',
);

mojo->post_ok( '/user/verify/' . $user->{user_id} . '/' . substr( $user->{passwd}, 0, 12 ) )
    ->status_is(302)
    ->header_is( location => url('/') )
    ->get_ok('/')
    ->status_is(200)
    ->attr_is( 'dialog#message', 'class', 'success' )
    ->text_like( 'dialog#message', qr|Successfully verified| );

is(
    stuff('dq')->get( 'user', ['active'], { email => '?' } )->run($email)->value,
    1,
    'user verified',
);

teardown;
