use Test2::V0;
use exact -conf;
use Omniframe::Test::App;
use QuizSage::Test;

setup;

mojo->get_ok( '/api/v1/bible/' . $_ )->status_is(401) for ( qw(
    books
    identify
    reference/parse
    structure
) );

api_login;

mojo->get_ok('/api/v1/bible/books')->status_is(200)->json_is( '/0' => 'Genesis' );

mojo->get_ok(
    '/api/v1/bible/identify',
    form => {
        books => [ 'Gen', 'Lev', '3 Mac' ],
    },
)->status_is(200)->json_is( [ ( {
    name  => T(),
    count => 3,
    books => [ 'Genesis', 'Leviticus', '3 Maccabees' ],
} ) x 2 ] );

mojo->get_ok(
    '/api/v1/bible/reference/parse',
    form => {
        text => 'Text with I Pet 3:16 and Rom 12:13-14,17 references in it.',
    },
)->status_is(200)->json_is( '/refs' => 'Romans 12:13-14, 17; 1 Peter 3:16' );

mojo->get_ok('/api/v1/bible/structure')->status_is(200)->json_is( '/0/0' => 'Genesis' );

teardown;
