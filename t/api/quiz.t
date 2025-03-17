use Test2::V0;
use exact -conf;
use Omniframe::Test::App;
use QuizSage::Test;

setup;

mojo->get_ok( '/api/v1/quiz/' . $_ )->status_is(401) for ( qw(
    distribution
    verses
    1/data
) );

api_login;

mojo->get_ok(
    '/api/v1/quiz/distribution',
    form => {
        bibles       => [ qw( NIV ESV BSB ) ],
        teams_counts => 3,
    },
)->status_is(200)->json_is(
    array {
        all_items hash {
            field $_ => E() for ( qw( id type ) );
            etc;
        };
        etc;
    }
);

teardown;
