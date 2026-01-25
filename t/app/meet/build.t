use Test2::V0;
use exact -conf;
use Omniframe::Test::App;
use QuizSage::Model::Season;
use QuizSage::Model::Meet;
use QuizSage::Test;

setup;
my ($user) = user;
my $csrf = csrf;

is(
    $user->data->{settings}{meet_passwd},
    undef,
    'meet_password not yet set',
);

mojo->post_ok( '/meet/passwd', form => { meet_passwd => 'test_meet_passwd', @$csrf } )
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

mojo->post_ok( '/meet/passwd', form => { meet_passwd => 'test_meet_passwd', @$csrf } )
    ->status_is(302)
    ->header_is( location => url('/') )
    ->get_ok('/')
    ->status_is(200)
    ->content_like( qr|
        \bomniframe\s*\.\s*memo\s*\([\s\{"]+
        class[":\s]+success\b[":\s,]+
        message[":\s]+Successfully\s+set\s+your\s+meet\s+official\s+password
    |x );

is(
    length( $user->load( $user->id )->data->{settings}{meet_passwd} // '' ),
    46,
    'meet_password set',
);

( my $name = lc( crypt( $$ . ( time + rand ), 'gs' ) ) ) =~ s/[^a-z0-9]+//g;
my $meet = QuizSage::Model::Meet->new->create({
    season_id => QuizSage::Model::Season->new->create({ name => 'Season ' . $name })->id,
    name      => 'Meet ' . $name,
    passwd    => 'test_meet_passwd',
});

my $material_dq = stuff('obj')->dq('material');
$material_dq->begin_work;
my $bible_insert = $material_dq->sql(q{
    INSERT INTO bible (acronym) VALUES (?)
    ON CONFLICT(acronym) DO NOTHING
});
$bible_insert->run( conf->get( qw( quiz_defaults bible ) ) );
$bible_insert->run($_) for ( qw( BSB ESV NASB NIV ) );

my $mock = mock $meet => ( override => [
    create_material_json   => 1,
    add_distributions      => 1,
    build_settings_cleanup => 1,
] );

$meet->build;

$material_dq->rollback;

mojo->get_ok( '/meet/' . $meet->id . '/state' )
    ->status_is(200)
    ->text_is( 'h3:nth-of-type(1)', 'Bracket: Preliminary' )
    ->text_is( 'h3:nth-of-type(2)', 'Bracket: Auxiliary' )
    ->text_is( 'h3:nth-of-type(3)', 'Bracket: Top 9' )
    ->text_is( 'h3:nth-of-type(1) + div b', 'Instructions and Announcements' )
    ->text_is( 'h3:nth-of-type(1) ~ div > div:nth-child(1) + div b', 'Quiz: 1' );

mojo->get_ok( '/meet/' . $meet->id . '/roster' )
    ->status_is(200)
    ->text_is( 'div:nth-of-type(1) b', 'TEAM 1' )
    ->text_is( 'div:nth-of-type(1) ul li:nth-of-type(1) b', 'Alpha Bravo' )
    ->text_like( 'div:nth-of-type(1) ul li:nth-of-type(1)', qr/^\s*ESV\s*$/ )
    ->text_is( 'div:nth-of-type(1) ul li:nth-of-type(1) i', '(Veteran, Youth)' );

mojo->get_ok( '/meet/' . $meet->id . '/distribution' )
    ->status_is(200)
    ->text_is( 'details:nth-of-type(1) div.summary_box b', 'Quiz: 1' );

mojo->get_ok( '/meet/' . $meet->id . '/stats' )
    ->status_is(200)
    ->text_is( 'details:nth-of-type(1) summary', 'Quizzers by Points Average' )
    ->text_is( 'details:nth-of-type(2) summary', 'Quizzers with VRAs' )
    ->text_is( 'details:last-of-type summary', 'Organizations by Average Points Per Team' );

mojo->get_ok( '/meet/' . $meet->id . '/board/1' )
    ->status_is(200)
    ->text_is( 'h1', 'Scoreboard Room 1' );

teardown;
