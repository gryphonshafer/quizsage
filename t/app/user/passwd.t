use Test2::V0;
use exact -conf;
use Omniframe::Test::App;
use QuizSage::Model::User;
use QuizSage::Test;

setup;
my ( $user, $email ) = user;
my $csrf = csrf;

mojo->app->hook( before_routes => sub ($c) { $c->set_captcha_value(1234567) } );

mojo->post_ok( '/user/forgot_password', form => { email => $email, @$csrf } )
    ->status_is(200)
    ->content_like( qr|
        \bomniframe\s*\.\s*memo\s*\([\s\{"]+
        class[":\s]+error\b[":\s,]+
        message[":\s]+The\s+captcha\s+sequence\s+provided\s+does\s+not\s+match
    |x );

mojo->post_ok( '/user/forgot_password', form => { email => $email, captcha => 1234567, @$csrf } )
    ->status_is(302)
    ->header_is( location => url('/') )
    ->get_ok('/')
    ->status_is(200)
    ->content_like( qr|
        \bomniframe\s*\.\s*memo\s*\([\s\{"]+
        class[":\s]+success\b[":\s,]+
        message[":\s]+Sent\s+email\s+to:
    |x );

mojo->post_ok(
    '/user/forgot_password',
    form => {
        email   => 'not_exists_' . $email,
        captcha => 1234567,
        @$csrf,
    }
)
    ->status_is(200)
    ->content_like( qr|
        \bomniframe\s*\.\s*memo\s*\([\s\{"]+
        class[":\s]+error\b[":\s,]+
        message[":\s]+Failed\s+to\s+load\s+user
    |x );

my $old_password_encrypted = $user->data->{passwd};
my $good_token             = QuizSage::Model::User::_encode_token( $user->id );
my $bad_token              = QuizSage::Model::User::_encode_token(0);

mojo->post_ok(
    '/user/reset_password/' . $bad_token,
    form => { passwd => 'new_poor_but_long_password', @$csrf },
)
    ->status_is(200)
    ->content_like( qr|
        \bomniframe\s*\.\s*memo\s*\([\s\{"]+
        class[":\s]+error\b[":\s,]+
        message[":\s]+Failed\s+to\s+reset\s+password
    |x );

mojo->post_ok(
    '/user/reset_password/' . $good_token,
    form => { passwd => 'short', @$csrf },
)
    ->status_is(200)
    ->content_like( qr|
        \bomniframe\s*\.\s*memo\s*\([\s\{"]+
        class[":\s]+error\b[":\s,]+
        message[":\s]+Password\s+supplied\s+is\s+not\s+at\s+least
    |x );

my $new_password_encrypted = $user->load( $user->id )->data->{passwd};
is( $old_password_encrypted, $new_password_encrypted, 'password not changed' );

mojo->post_ok(
    '/user/reset_password/' . $good_token,
    form => { passwd => 'new_poor_but_long_password', @$csrf },
)
    ->status_is(302)
    ->header_is( location => url('/') )
    ->get_ok('/')
    ->status_is(200)
    ->content_like( qr|
        \bomniframe\s*\.\s*memo\s*\([\s\{"]+
        class[":\s]+success\b[":\s,]+
        message[":\s]+Successfully\s+reset\s+password
    |x );

my $new_password_encrypted_2 = $user->load( $user->id )->data->{passwd};
isnt( $old_password_encrypted, $new_password_encrypted_2, 'password changed' );

teardown;
