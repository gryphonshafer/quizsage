use Test2::V0;
use exact -conf;
use QuizSage::Model::Quiz;
use QuizSage::Model::User;

my $obj;
ok( lives { $obj = QuizSage::Model::Quiz->new }, 'new' ) or note $@;
DOES_ok( $obj, $_ ) for ( qw( Omniframe::Role::Model QuizSage::Role::JSApp ) );
can_ok( $obj, qw(
    socket create save delete
    freeze thaw
    pickup
    latest_quiz_in_meet_room
    ensure_material_json_exists
    create_material_json_from_label
) );

$obj->dq->begin_work;
$obj->dq('material')->begin_work;

my $user = QuizSage::Model::User->new->create({
    email      => crypt( $$ . ( time + rand ), 'gs' ) . '@example.com',
    passwd     => 'password',
    first_name => 'First',
    last_name  => 'Last',
    phone      => '1234567890',
});
$user->save({ active => 1 });

$obj->dq('material')->sql(q{
    INSERT INTO bible (acronym) VALUES (?)
    ON CONFLICT(acronym) DO NOTHING
})->run( $user->conf->get( qw( quiz_defaults bible ) ) );

my $mock = mock $obj => ( override => [ material_json => sub { +{
    label       => 'label',
    description => 'description',
    id          => 'id',
} } ] );

my $pickup_quiz;
ok(
    lives { $pickup_quiz = $obj->pickup( {}, $user ) },
    q/pickup(...)/,
) or note $@;

isa_ok( $pickup_quiz, 'QuizSage::Model::Quiz' );
ok( $pickup_quiz->id, 'id' );

my $data = $pickup_quiz->data;
ok( $data->{settings}{teams}[0]{name}, 'team 1 name' );
ok( $data->{settings}{material}{label}, 'material label' );
ok( $data->{settings}{distribution}, 'distribution' );

ok(
    lives { $obj->latest_quiz_in_meet_room( 42, 1 ) },
    q/latest_quiz_in_meet_room/,
) or note $@;

ok(
    lives { $pickup_quiz->ensure_material_json_exists },
    q/ensure_material_json_exists/,
) or note $@;

$obj->dq->rollback;
$obj->dq('material')->rollback;

done_testing;
