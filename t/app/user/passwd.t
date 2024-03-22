use Test2::V0;
use exact -conf;
use Omniframe::Test::App;
use QuizSage::Model::User;

setup;

my $email = stuff('email');
my $user  = QuizSage::Model::User->new->create({
    email      => $email,
    passwd     => 'terrible_but_long_enough_password',
    first_name => 'First Name',
    last_name  => 'Last Name',
    phone      => '1234567890',
});
$user->save({ active => 1 });

mojo->post_ok( '/user/forgot_password' => form => { email => $email } )
    ->status_is(302)
    ->header_is( location => url('/') )
    ->get_ok('/')
    ->status_is(200)
    ->attr_is( 'dialog#message', 'class', 'success' )
    ->text_like( 'dialog#message', qr|Sent email to:| );

mojo->post_ok( '/user/forgot_password' => form => { email => 'not_exists_' . $email } )
    ->status_is(200)
    ->attr_is( 'dialog#message', 'class', 'error' )
    ->text_like( 'dialog#message', qr|Failed to load user| );

my $old_password_encrypted = $user->data->{passwd};

mojo->post_ok(
    '/user/reset_password/' . $user->id . '/a1b2c3d4',
    form => { passwd => 'new_poor_but_long_password' },
)
    ->status_is(200)
    ->attr_is( 'dialog#message', 'class', 'error' )
    ->text_like( 'dialog#message', qr|Failed to reset password| );

mojo->post_ok(
    '/user/reset_password/' . $user->id . '/' . substr( $old_password_encrypted, 0, 12 ),
    form => { passwd => 'short' },
)
    ->status_is(200)
    ->attr_is( 'dialog#message', 'class', 'error' )
    ->text_like( 'dialog#message', qr|Password supplied is not at least| );

my $new_password_encrypted = $user->load( $user->id )->data->{passwd};
is( $old_password_encrypted, $new_password_encrypted, 'password not changed' );

mojo->post_ok(
    '/user/reset_password/' . $user->id . '/' . substr( $old_password_encrypted, 0, 12 ),
    form => { passwd => 'new_poor_but_long_password' },
)
    ->status_is(302)
    ->header_is( location => url('/') )
    ->get_ok('/')
    ->status_is(200)
    ->attr_is( 'dialog#message', 'class', 'success' )
    ->text_like( 'dialog#message', qr|Successfully reset password| );

my $new_password_encrypted_2 = $user->load( $user->id )->data->{passwd};
isnt( $old_password_encrypted, $new_password_encrypted_2, 'password changed' );

teardown;
