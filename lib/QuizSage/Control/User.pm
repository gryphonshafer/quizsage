package QuizSage::Control::User;

use exact 'Mojolicious::Controller';
use QuizSage::Model::User;

sub create ($self) {
    if ( my %params = $self->req->params->to_hash->%* ) {
        my @fields = qw( email passwd first_name last_name phone );

        try {
            die 'Email, password, first and last name, and phone fields must be filled in'
                if ( grep { length $params{$_} == 0 } @fields );

            unless ( $self->stash('user') ) {
                my $user = QuizSage::Model::User->new->create({ map { $_ => $params{$_} } @fields });

                if ( $user and $user->data ) {
                    $user->send_email( 'verify_email', $self->url_for('/user/verify') );

                    $self->flash(
                        message => {
                            type => 'success',
                            text => 'Successfully created user. Watch for the verification email.',
                        }
                    );
                    $self->redirect_to('/');
                }
            }
        }
        catch ($e) {
            $e =~ s/\s+at\s+(?:(?!\s+at\s+).)*[\r\n]*$//;
            $e =~ s/^"([^""]+)"/ '"' . join( ' ', map { ucfirst($_) } split( '_', $1 ) ) . '"' /e;
            $e =~ s/DBD::\w+::st execute failed:\s*//;
            $e .= '. Please try again.';

            $e = "Value in $1 field is already registered under an existing user account."
                if ( $e =~ /UNIQUE constraint failed/ );

            $self->info("User CRUD failure: $e");
            $self->stash( message => $e, %params );
        }
    }
}

sub verify ($self) {
    if ( QuizSage::Model::User->new->verify( $self->stash('user_id'), $self->stash('user_hash') ) ) {
        $self->flash(
            message => {
                type => 'success',
                text => 'Successfully verified this user account. You may now login with your credentials.',
            }
        );
    }
    else {
        $self->flash( message => 'Unable to verify user account using the link provided.' );
    }

    $self->redirect_to('/');
}

sub forgot_password ($self) {
    if ( my $email = $self->param('email') ) {
        try {
            QuizSage::Model::User->new->load({ email => $email })
                ->send_email( 'reset_password', $self->url_for('/user/reset_password') );

            $self->flash(
                message => {
                    type => 'success',
                    text => 'Watch for the password reset email.',
                }
            );

            $self->redirect_to('/');
        }
        catch ($e) {
            $e =~ s/\s+at\s+(?:(?!\s+at\s+).)*[\r\n]*$//;
            $self->stash( message => $e );
        }
    }
}

sub reset_password ($self) {
    if ( my $passwd = $self->param('passwd') ) {
        if (
            QuizSage::Model::User->new->reset_password(
                $self->stash('user_id'),
                $self->stash('user_hash'),
                $passwd,
            )
        ) {
            $self->flash(
                message => {
                    type => 'success',
                    text => 'Successfully reset password. Login with your new password.',
                }
            );
            return $self->redirect_to('/');
        }
        else {
            $self->stash( message => 'Failed to reset password.' );
        }
    }
}

sub login ($self) {
    try {
        my $user = QuizSage::Model::User->new->login( map { $self->param($_) } qw( email passwd ) );

        $self->info( 'Login success for: ' . $user->data->{email} );
        $self->session(
            user_id           => $user->id,
            last_request_time => time,
        );
    }
    catch {
        $self->info( 'Login failure for ' . $self->param('email') );
        $self->flash( message =>
            'Login failed. Please try again, or try the ' .
            '<a href="' . $self->url_for('/user/reset_password') . '">Reset Password page</a>.'
        );
    };

    $self->redirect_to('/');
}

sub logout ($self) {
    $self->info(
        'Logout requested from: ' .
        ( ( $self->stash('user') ) ? $self->stash('user')->data->{email} : '(Unlogged-in user)' )
    );
    $self->session(
        user_id           => undef,
        last_request_time => undef,
    );

    $self->redirect_to('/');
}

1;

=head1 NAME

QuizSage::Control::User

=head1 DESCRIPTION

This class is a subclass of L<Mojolicious::Controller> and provides handlers
for "user" actions.

=head1 METHODS

=head2 create

Handler for user create.

=head2 verify

Handler for verify.

=head2 forgot_password

Handler for forgot password.

=head2 reset_password

Handler for reset password.

=head2 login

Handler for login.

=head2 logout

Handler for logout.

=head1 INHERITANCE

L<Mojolicious::Controller>.
