use Test2::V0;
use exact -conf;
use Mojo::URL;
use QuizSage::Model::User;

my $obj;
ok( lives { $obj = QuizSage::Model::User->new }, 'new' ) or note $@;
DOES_ok( $obj, "Omniframe::Role::$_" ) for ( qw( Bcrypt Model ) );
can_ok( $obj, qw(
    active
    freeze thaw send_email verify reset_password login qm_auth
) );

$obj->dq->begin_work;

like(
    dies { $obj->create({}) },
    qr/Email not provided properly/,
    'create({})',
);

like(
    dies { $obj->create({ email => 'bad_email' }) },
    qr/Email not provided properly/,
    q/create({ email => 'bad_email' })/,
);

like(
    dies { $obj->create({
        email      => 'good_email@example.com',
        passwd     => 'short',
        first_name => 'first_name',
        last_name  => 'last_name',
    }) },
    qr/Password supplied is not at least/,
    q/create({ passwd => 'short' })/,
);

like(
    dies { $obj->create({
        email      => 'good_email@example.com',
        passwd     => 'terrible_but_long_password',
        first_name => 'first_name',
        last_name  => 'last_name',
        phone      => 'short',
    }) },
    qr/Phone supplied is not at least/,
    q/create({ phone => 'short' })/,
);

ok(
    lives { $obj->create({
        email      => 'good_email@example.com',
        passwd     => 'terrible_but_long_password',
        first_name => 'first_name',
        last_name  => 'last_name',
        phone      => '1234567890',
    }) },
    q{create({...})},
) or note $@;

my $email_obj  = Omniframe::Class::Email->new( type => 'verify_email' );
my $mock_email = mock 'Omniframe::Class::Email' => (
    override => [
        new  => sub { $email_obj },
        send => sub { @_ },
    ]
);

ok(
    lives { $obj->send_email( 'verify_email', Mojo::URL->new('http://localhost:3000') ) },
    q/send_email(...)/,
) or note $@;

ok(
    $obj->verify( $obj->id, substr( $obj->data->{passwd}, 0, 12 ) ),
    q/verify(...)/,
);

ok(
    $obj->reset_password( $obj->id, substr( $obj->data->{passwd}, 0, 12 ), 'new_password' ),
    q/reset_password(...)/,
);

$obj->load( $obj->id );

like(
    dies { $obj->login( 'good_email@example.com', 'bad_password' ) },
    qr/Failed to load user/,
    q/login(...) with bad password/,
);

ok(
    $obj->login( 'good_email@example.com', 'new_password' ),
    q/login(...) with good password/,
);

my $meet_obj = QuizSage::Model::Meet->new;
my $mock_meet = mock 'QuizSage::Model::Meet' => (
    override => [
        new  => sub { $meet_obj },
        load => sub { $meet_obj },
        data => sub { +{ passwd => 'a1b2c3d4e5f6a1b2c3d4e5f6' } },
    ],
);
ok( not( $obj->qm_auth($meet_obj) ), 'qm_auth(...) invalid' );
$obj->data->{settings}{meet_passwd} = 'a1b2c3d4e5f6a1b2c3d4e5f6';
ok( $obj->qm_auth($meet_obj), 'qm_auth(...) valid' );

$obj->dq->rollback;

done_testing;
