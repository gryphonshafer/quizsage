use Test2::V0;
use exact -conf;
use Omniframe::Test::App;
use QuizSage::Model::User;
use QuizSage::Model::Season;
use QuizSage::Model::Meet;

setup;

my $user = QuizSage::Model::User->new->create({
    email      => stuff('email'),
    passwd     => 'terrible_but_long_enough_password',
    first_name => 'First Name',
    last_name  => 'Last Name',
    phone      => '1234567890',
});
$user->save({ active => 1 });

is(
    $user->data->{settings}{meet_passwd},
    undef,
    'meet_password not yet set',
);

mojo->post_ok( '/meet/passwd', form => { meet_passwd => 'test_meet_passwd' } )
    ->status_is(302)
    ->header_is( location => url('/') )
    ->get_ok('/')
    ->status_is(200)
    ->attr_is( 'dialog#message', 'class', 'error' )
    ->text_like( 'dialog#message', qr|Login required for the previously requested resource| );

mojo->app->hook( before_routes => sub ($c) { $c->session( user_id => $user->id ) } );

mojo->post_ok( '/meet/passwd', form => { meet_passwd => 'test_meet_passwd' } )
    ->status_is(302)
    ->header_is( location => url('/') )
    ->get_ok('/')
    ->status_is(200)
    ->attr_is( 'dialog#message', 'class', 'success' )
    ->text_like( 'dialog#message', qr|Successfully set your meet official password| );

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
$bible_insert->run( $user->conf->get( qw( quiz_defaults bible ) ) );
$bible_insert->run($_) for ( qw( BSB ESV NASB NIV ) );

my $mock = mock $meet => ( override => [
    _create_material_json   => 1,
    _add_distributions      => 1,
    _build_settings_cleanup => 1,
] );

$meet->build;

$material_dq->rollback;

mojo->get_ok( '/meet/' . $meet->id . '/state' )
    ->status_is(200)
    ->text_is( 'h3:nth-of-type(1)', 'Bracket: Preliminary' )
    ->text_is( 'h3:nth-of-type(2)', 'Bracket: Auxiliary' )
    ->text_is( 'h3:nth-of-type(3)', 'Bracket: Top 9' )
    ->text_is( 'h3:nth-of-type(1) + div b', 'Instructions and Announcements' )
    ->text_like( 'h3:nth-of-type(1) ~ div > div:nth-child(1)', qr|Fri, Dec 1| )
    ->text_is( 'h3:nth-of-type(1) ~ div > div:nth-child(1) + div a b', 'Quiz: 1' );

mojo->get_ok( '/meet/' . $meet->id . '/roster' )
    ->status_is(200)
    ->text_is( 'div:nth-of-type(1) b', 'TEAM 1' )
    ->text_is( 'div:nth-of-type(1) ul li:nth-of-type(1) b', 'Alpha Bravo' )
    ->text_like( 'div:nth-of-type(1) ul li:nth-of-type(1)', qr/^\s*ESV\s*$/ )
    ->text_is( 'div:nth-of-type(1) ul li:nth-of-type(1) i', '(Veteran, Youth)' );

mojo->get_ok( '/meet/' . $meet->id . '/distribution' )
    ->status_is(200)
    ->text_is( 'h3:nth-of-type(1) ~ div > div:nth-child(1) b', 'Quiz: 1' );

mojo->get_ok( '/meet/' . $meet->id . '/stats' )
    ->status_is(200)
    ->text_is( 'details:nth-of-type(1) summary', 'Top 9 Rankings' )
    ->text_like( 'details:nth-of-type(2) summary', qr/^\s*All\s*Quizzers\s*by\s*Points\s*Average\s*$/ )
    ->text_is( 'details:last-of-type summary', 'Quizzers with VRAs' );

mojo->get_ok( '/meet/' . $meet->id . '/board/1' )
    ->status_is(200)
    ->text_is( 'h1', 'Scoreboard Room 1' );

teardown;
