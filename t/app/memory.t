use Test2::V0;
use exact -conf;
use Omniframe::Test::App;
use QuizSage::Test;

setup;
my ($user) = user;

mojo->get_ok($_)
    ->status_is(302)
    ->header_is( location => url('/') )
    ->get_ok('/')
    ->status_is(200)
    ->content_like( qr|
        \bomniframe\s*\.\s*memo\s*\([\s\{"]+
        class[":\s]+error\b[":\s,]+
        message[":\s]+Login\s+required\s+for\s+the\s+previously\s+requested\s+resource
    |x )
    for (
        '/memory/memorize',
        '/memory/review',
        '/memory/state',
    );

mojo->app->hook( before_routes => sub ($c) { $c->session( user_id => $user->id ) } );

mojo->get_ok('/memory/memorize')
    ->status_is(200)
    ->text_is( title => 'QuizSage: Initial Memorization' );

mojo->get_ok('/memory/review')
    ->status_is(200)
    ->text_is( title => 'QuizSage: Memorization Review' );

mojo->get_ok('/memory/state')
    ->status_is(200)
    ->text_is( title => 'QuizSage: Memory State' );

teardown;
