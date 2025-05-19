use Test2::V0;
use exact -conf;
use Omniframe::Test::App;
use QuizSage::Test;

setup;
my ( $user, $email, $passwd ) = user;
my $csrf = csrf;

mojo->get_ok('/')
    ->status_is(200)
    ->header_is( 'content-type' => 'text/html;charset=UTF-8' )
    ->text_is( title => 'QuizSage' )
    ->attr_is( 'meta[charset]', 'charset', 'utf-8' )
    ->attr_like( 'link[rel="stylesheet"]:last-of-type', 'href', qr|\bapp.css\?version=\d+| )
    ->attr_is( 'main form', 'method', 'post' )
    ->attr_is( 'main form', 'action', url('/user/login') );

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

mojo->get_ok('/user/logout')
    ->status_is(302)
    ->header_is( location => url('/') )
    ->get_ok('/')
    ->status_is(200)
    ->attr_is( 'main form', 'method', 'post' );

mojo->post_ok(
        '/user/login',
        form => {
            email  => $email,
            passwd => 'incorrect_passwd',
            @$csrf,
        },
    )
    ->status_is(302)
    ->header_is( location => url('/') )
    ->get_ok('/')
    ->status_is(200)
    ->content_like( qr|
        \bomniframe\s*\.\s*memo\s*\([\s\{"]+
        class[":\s]+error\b[":\s,]+
        message[":\s]+Login\s+failed
    |x );

mojo->get_ok('/set/theme/theme_name')
    ->status_is(302)
    ->header_is( location => url('/set/theme/theme_name') )
    ->get_ok('/')
    ->status_is(200)
    ->attr_like( 'html', 'class', qr/\btheme-theme_name\b/ );

teardown;
