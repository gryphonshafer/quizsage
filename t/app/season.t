use Test2::V0;
use exact -conf;
use Omniframe::Test::App;
use QuizSage::Model::Season;
use QuizSage::Test;

setup;

my ($user) = user;

my $season = QuizSage::Model::Season->new->create({ name => 'Season Test' });

mojo->get_ok( '/season/' . $season->id . '/stats' )
    ->status_is(302)
    ->header_is( location => url('/') )
    ->get_ok('/')
    ->status_is(200)
    ->content_like( qr|
        \bomniframe\s*\.\s*memo\s*\([\s\{"]+
        class[":\s]+error\b[":\s,]+
        message[":\s]+Login\s+required\s+for\s+the\s+previously\s+requested\s+resource
    |x );

mojo->app->hook( before_routes => sub ($c) { $c->session( user_id => $user->id ) } );

mojo->get_ok( '/season/' . $season->id . '/stats' )
    ->status_is(200)
    ->text_like( 'details:nth-of-type(1) summary', qr/^\s*All\s*Quizzers\s*by\s*Points\s*Average\s*$/ )
    ->text_is( 'details:last-of-type summary', 'Quizzers with VRAs' );

teardown;
