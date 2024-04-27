use Test2::V0;
use exact -conf;
use Mojo::DOM;
use Omniframe::Test::App;
use QuizSage::Model::User;
use QuizSage::Model::Quiz;

setup;

my $user = QuizSage::Model::User->new->create({
    email      => stuff('email'),
    passwd     => 'terrible_but_long_enough_password',
    first_name => 'First Name',
    last_name  => 'Last Name',
    phone      => '1234567890',
});
$user->save({ active => 1 });

my $dom;
mojo->app->hook( before_routes => sub ($c) { $c->session( user_id => $user->id ) } );
mojo->app->hook( after_render => sub ( $c, $output, $format ) { $dom = Mojo::DOM->new($$output) } );

mojo->get_ok('/quiz/pickup/setup')
    ->status_is(200)
    ->element_exists('input[name="bible"]')
    ->element_exists('textarea[name="roster_data"]')
    ->element_exists('textarea[name="material_label"]');

my $default_bible  = $dom->at('input[name="bible"]')->attr('value');
my $roster_data    = $dom->at('textarea[name="roster_data"]')->text;
my $material_label = $dom->at('textarea[name="material_label"]')->text;

my $mock = mock 'QuizSage::Model::Quiz' => ( override => [
    new    => sub { $_[0] },
    pickup => sub { $_[0] },
    id     => sub { 42 },
] );

mojo->post_ok(
    '/quiz/pickup/setup',
    form => {
        default_bible  => $default_bible,
        roster_data    => $roster_data,
        material_label => $material_label,
    },
)
    ->status_is(302)
    ->header_is( location => '/quiz/pickup/42' );

mojo->get_ok('/drill/setup')
    ->status_is(200)
    ->element_exists('textarea[name="material_label"]');

my $drill_material_label = $dom->at('textarea[name="material_label"]')->text;

mojo->post_ok(
    '/drill/setup',
    form => {
        material_label => $drill_material_label,
    },
)
    ->status_is(302)
    ->header_is( location => '/drill' );

teardown;
