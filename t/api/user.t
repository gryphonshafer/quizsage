use Test2::V0;
use exact -conf;
use Omniframe::Test::App;
use QuizSage::Test;

setup;
my ( $user, $email, $passwd ) = user;

mojo->get_ok('/api/v1/bible/books')->status_is(401);

mojo->post_ok(
    '/user/login',
    form => {
        email  => $email,
        passwd => $passwd,
    },
);

mojo->get_ok('/api/v1/bible/books')->status_is(200)->json_is( '/0' => 'Genesis' );
mojo->get_ok('/user/logout');
mojo->get_ok('/api/v1/bible/books')->status_is(401);

mojo->post_ok(
    '/api/v1/user/login',
    form => {
        email    => $email,
        password => $passwd,
    },
)->status_is(200)->json_is( '/success' => 1 );

mojo->get_ok('/api/v1/bible/books')->status_is(200)->json_is( '/0' => 'Genesis' );
mojo->post_ok('/api/v1/user/logout')->status_is(200);
mojo->get_ok('/api/v1/bible/books')->status_is(401);

teardown;
