use Test2::V0;
use exact -conf;
use Omniframe::Test::App;
use QuizSage::Test;

setup;
my ( $user, $email, $passwd ) = user;
my $csrf = csrf;

mojo->post_ok(
        '/user/login',
        form => {
            email  => $email,
            passwd => $passwd,
            @$csrf,
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
            @$csrf,
        },
    )
    ->status_is(302)
    ->header_is( location => url('/') )
    ->get_ok('/')
    ->status_is(200)
    ->content_like( qr|
        \bomniframe\s*\.\s*memo\s*\([\s\{"]+
        class[":\s]+success\b[":\s,]+
        message[":\s]+Successfully\s+edited\s+user\s+profile
    |x );

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
        '/user/profile',
        form => {
            passwd => 'short',
            @$csrf,
        },
    )
    ->status_is(200)
    ->content_like( qr|
        \bomniframe\s*\.\s*memo\s*\([\s\{"]+
        class[":\s]+error\b
    |x );

teardown;
