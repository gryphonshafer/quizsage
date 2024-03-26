use Test2::V0;
use exact -conf;
use Omniframe::Test::App;
use QuizSage::Model::User;

setup;

my $email  = stuff('email');
my $passwd = 'terrible_but_long_enough_password';
my $user   = QuizSage::Model::User->new;

$user->create({
    email      => $email,
    passwd     => $passwd,
    first_name => 'First Name',
    last_name  => 'Last Name',
    phone      => '1234567890',
});
$user->save({ active => 1 });

mojo->get_ok('/')
    ->status_is(200)
    ->header_is( 'content-type' => 'text/html;charset=UTF-8' )
    ->text_is( title => 'QuizSage' )
    ->attr_is( 'meta[charset]', 'charset', 'utf-8' )
    ->attr_like( 'link[rel="stylesheet"]:last-of-type', 'href', qr|\bapp.css\?version=\d+| )
    ->attr_is( 'form', 'method', 'post' )
    ->attr_is( 'form', 'action', url('/user/login') );

my $captcha_sequence;
mojo->app->hook( after_dispatch => sub ($c) { $captcha_sequence = $c->session('captcha') } );

mojo->get_ok('/captcha')
    ->status_is(200)
    ->header_is( 'content-type' => 'image/png' );

like( $captcha_sequence, qr/^\d{7}$/, 'captcha sequence is 7 digits' );

mojo->app->hook( before_routes => sub ($c) { $c->session( captcha => 1234567 ) } );

mojo->post_ok(
        '/user/login',
        form => {
            email   => $email,
            passwd  => $passwd,
            captcha => '12-345-67',
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
    ->attr_is( 'form', 'method', 'post' );

mojo->post_ok(
        '/user/login',
        form => {
            email   => $email,
            passwd  => 'incorrect_passwd',
            captcha => '12-345-67',
        },
    )
    ->status_is(302)
    ->header_is( location => url('/') )
    ->get_ok('/')
    ->status_is(200)
    ->attr_is( 'dialog#message', 'class', 'error' )
    ->text_like( 'dialog#message', qr|Login failed| );

mojo->post_ok(
        '/user/login',
        form => {
            email   => $email,
            passwd  => 'incorrect_passwd',
            captcha => '1138',
        },
    )
    ->status_is(302)
    ->header_is( location => url('/') )
    ->get_ok('/')
    ->status_is(200)
    ->attr_is( 'dialog#message', 'class', 'error' )
    ->text_like( 'dialog#message', qr|captcha sequence provided does not match| );

mojo->get_ok('/set/theme/theme_name')
    ->status_is(302)
    ->header_is( location => url('/set/theme/theme_name') )
    ->get_ok('/')
    ->status_is(200)
    ->attr_like( 'html', 'class', qr/\btheme-theme_name\b/ );

teardown;