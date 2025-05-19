use Test2::V0;
use exact -conf;
use Omniframe::Test::App;
use QuizSage::Test;

setup;
my $csrf = csrf;

mojo->get_ok('/user/create')
    ->status_is(200)
    ->attr_is( 'main form', 'method', 'post' );

my $email  = email;
my $passwd = 'terrible_but_long_enough_password';

my $captcha_sequence;
mojo->app->hook( after_dispatch => sub ($c) { $captcha_sequence = $c->get_captcha_value } );

mojo->get_ok('/captcha')
    ->status_is(200)
    ->header_is( 'content-type' => 'image/png' );

like( $captcha_sequence, qr/^\d{7}$/, 'captcha sequence is 7 digits' );

mojo->app->hook( before_routes => sub ($c) { $c->set_captcha_value(1234567) } );

mojo->post_ok(
        '/user/create',
        form => {
            email      => $email,
            passwd     => $passwd,
            first_name => 'First Name',
            last_name  => 'Last Name',
            phone      => '1234567890',
            @$csrf,
        },
    )
    ->status_is(200)
    ->content_like( qr|
        \bomniframe\s*\.\s*memo\s*\([\s\{"]+
        class[":\s]+error\b[":\s,]+
        message[":\s]+The\s+captcha\s+sequence\s+provided\s+does\s+not\s+match
    |x );

mojo->post_ok(
        '/user/create',
        form => {
            email      => $email,
            passwd     => $passwd,
            first_name => 'First Name',
            last_name  => 'Last Name',
            phone      => '123',
            captcha    => 1234567,
            @$csrf,
        },
    )
    ->status_is(200)
    ->content_like( qr|
        \bomniframe\s*\.\s*memo\s*\([\s\{"]+
        class[":\s]+error\b[":\s,]+
        message[":\s]+Phone\s+supplied\s+is\s+not\s+at\s+least\s+10\s+digits\s+in\s+length
    |x );

mojo->post_ok(
        '/user/create',
        form => {
            email      => $email,
            passwd     => $passwd,
            first_name => 'First Name',
            last_name  => 'Last Name',
            phone      => '1234567890',
            captcha    => 1234567,
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
        message[":\s]+Successfully\s+created\s+user
    |x );

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

my $good_token = QuizSage::Model::User::_encode_token( $user->{user_id} );
my $bad_token  = QuizSage::Model::User::_encode_token(0);

mojo->post_ok( '/user/verify/' . $bad_token, form => {@$csrf} )
    ->status_is(302)
    ->header_is( location => url('/') )
    ->get_ok('/')
    ->status_is(200)
    ->content_like( qr|
        \bomniframe\s*\.\s*memo\s*\([\s\{"]+
        class[":\s]+error\b[":\s,]+
        message[":\s]+Unable\s+to\s+verify
    |x );

is(
    stuff('dq')->get( 'user', ['active'], { email => '?' } )->run($email)->value,
    0,
    'user not verified (yet)',
);

mojo->post_ok( '/user/verify/' . $good_token, form => {@$csrf} )
    ->status_is(302)
    ->header_is( location => url('/') )
    ->get_ok('/')
    ->status_is(200)
    ->content_like( qr|
        \bomniframe\s*\.\s*memo\s*\([\s\{"]+
        class[":\s]+success\b[":\s,]+
        message[":\s]+Successfully\s+verified
    |x );

is(
    stuff('dq')->get( 'user', ['active'], { email => '?' } )->run($email)->value,
    1,
    'user verified',
);

teardown;
