package QuizSage::Test;

use exact -conf;
use Omniframe::Test::App;
use QuizSage::Model::User;

exact->export( qw{ user api_login });

sub user {
    my $email  = email;
    my $passwd = 'terrible_but_long_enough_password';

    my $user = QuizSage::Model::User->new->create({
        email      => $email,
        passwd     => $passwd,
        first_name => 'First Name',
        last_name  => 'Last Name',
        phone      => '1234567890',
    });

    $user->save({ active => 1 });

    return $user, $email, $passwd;
}

sub api_login {
    my ( $user, $email, $passwd ) = user;

    mojo->post_ok(
        '/api/v1/user/login',
        form => {
            email    => $email,
            password => $passwd,
        },
    )->status_is(200)->json_is( '/success' => 1 );
}

1;

=head1 NAME

QuizSage::Test

=head1 SYNOPSIS

    use exact -conf;
    use QuizSage::Test;

    my ( $user, $email, $passwd ) = user;

=head1 DESCRIPTION

This package provides functions to make QuizSage application testing a bit
simpler and easier.

=head1 FUNCTIONS

=head2 user

Creates a user in the database and returns the user, its email, and its password.

    my ( $user, $email, $passwd ) = user;

=head2 api_login

Creates a user and then calles the API C</user/login> endpoint with the user's
credentials.
