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
    ->attr_is( 'form#login_form', 'method', 'post' )
    ->attr_is( 'form#login_form', 'action', url('/user/login') );

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
    ->content_like( qr|Logged in as: <b>First Name</b>| );

mojo->get_ok('/user/logout')
    ->status_is(302)
    ->header_is( location => url('/') )
    ->get_ok('/')
    ->status_is(200)
    ->attr_is( 'form#login_form', 'method', 'post' );

mojo->post_ok(
        '/user/login',
        form => {
            email  => $email,
            passwd => 'incorrect_passwd',
        },
    )
    ->status_is(302)
    ->header_is( location => url('/') )
    ->get_ok('/')
    ->status_is(200)
    ->attr_is( 'dialog#message', 'class', 'error' )
    ->text_like( 'dialog#message', qr|Login failed| );

teardown;
