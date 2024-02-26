package QuizSage::Control::User;

use exact -conf, 'Mojolicious::Controller';
use QuizSage::Model::User;

sub account ($self) {
    my %params = $self->req->params->to_hash->%*;

    if ( $self->stash('account_action_type') eq 'create' and %params ) {
        my @fields = qw( email passwd first_name last_name phone );

        try {
            die 'Email, password, first and last name, and phone fields must be filled in'
                if ( grep { length $params{$_} == 0 } @fields );

            $self->_recaptcha;

            unless ( $self->stash('user') ) {
                my $user = QuizSage::Model::User->new->create({ map { $_ => $params{$_} } @fields });

                if ( $user and $user->data ) {
                    $user->send_email( 'verify_email', $self->url_for('/user/verify') );

                    my $email = {
                        to   => $user->data->{email},
                        from => $user->conf->get( qw( email from ) ),
                    };
                    $email->{$_} =~ s/(<|>)/ ( $1 eq '<' ) ? '&lt;' : '&gt;' /eg for ( qw( to from ) );

                    $self->info( 'User create success: ' . $user->id );
                    $self->flash(
                        message => {
                            type => 'success',
                            text => join( ' ',
                                'Successfully created user with email address: ' .
                                    '<b>' . $email->{to} . '</b>.',
                                'Check your email for reception of the verification email.',
                                'If you don\'t see the verification email in a couple minutes, ' .
                                    'check your spam folder.',
                                'Contact <b>' . $email->{from} . '</b> if you need help.',
                            ),
                        }
                    );
                    $self->redirect_to('/');
                }
            }
        }
        catch ($e) {
            if ( $e =~ /human\-verification/i ) {
                $e =~ s/\s+at\s+(?:(?!\s+at\s+).)*[\r\n]*$//;
                $self->info('reCaptcha score too low');
                $self->stash( message => $e );
            }
            else {
                $e =~ s/\s+at\s+(?:(?!\s+at\s+).)*[\r\n]*$//;
                $e =~ s/^"([^""]+)"/ '"' . join( ' ', map { ucfirst($_) } split( '_', $1 ) ) . '"' /e;
                $e =~ s/DBD::\w+::st execute failed:\s*//;
                $e .= '. Please try again.';

                $e = "Value in $1 field is already registered under an existing user account."
                    if ( $e =~ /UNIQUE constraint failed/ );

                $self->info("User create failure: $e");
                $self->stash( message => $e, %params );
            }
        }
    }

    elsif ( $self->stash('account_action_type') eq 'profile' and not %params ) {
        $self->stash( $_ => $self->stash('user')->data->{$_} ) for ( qw( first_name last_name email phone ) );
    }

    elsif ( $self->stash('account_action_type') eq 'profile' and %params ) {
        my @fields = qw( email first_name last_name phone );

        try {
            die 'Email, first and last name, and phone fields must be filled in'
                if ( grep { length $params{$_} == 0 } @fields );

            $self->stash('user')->data->{$_} = $params{$_} for (@fields);
            $self->stash('user')->data->{passwd} = $params{passwd} if ( $params{passwd} );
            $self->stash('user')->save;

            $self->info( 'User profile edit success: ' . $self->stash('user')->id );
            $self->flash(
                message => {
                    type => 'success',
                    text => 'Successfully edited user profile.',
                }
            );
            $self->redirect_to('/');
        }
        catch ($e) {
            $e =~ s/\s+at\s+(?:(?!\s+at\s+).)*[\r\n]*$//;
            $e =~ s/^"([^""]+)"/ '"' . join( ' ', map { ucfirst($_) } split( '_', $1 ) ) . '"' /e;
            $e =~ s/DBD::\w+::st execute failed:\s*//;
            $e .= '. Please try again.';

            $e = "Value in $1 field is already registered under an existing user account."
                if ( $e =~ /UNIQUE constraint failed/ );

            $self->info("User profile edit failure: $e");
            $self->stash( message => $e, %params );
        }
    }
}

sub verify ($self) {
    if ( QuizSage::Model::User->new->verify( $self->stash('user_id'), $self->stash('user_hash') ) ) {
        $self->info( 'User verified: ' . $self->stash('user_id') );
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
            $self->_recaptcha;

            my $user = QuizSage::Model::User->new->load( { email => $email }, 1 );
            if ( $user->data->{active} ) {
                $user->send_email( 'reset_password', $self->url_for('/user/reset_password') );
            }
            else {
                $user->send_email( 'verify_email', $self->url_for('/user/verify') );
            }

            my $email = {
                to   => $user->data->{email},
                from => $user->conf->get( qw( email from ) ),
            };
            $email->{$_} =~ s/(<|>)/ ( $1 eq '<' ) ? '&lt;' : '&gt;' /eg for ( qw( to from ) );

            $self->flash(
                message => {
                    type => 'success',
                    text => join( ' ',
                        'Sent email to: ' .
                            '<b>' . $email->{to} . '</b>.',
                        'Check your email for reception of the email.',
                        'If you don\'t see the email in a couple minutes, ' .
                            'check your spam folder.',
                        'Contact <b>' . $email->{from} . '</b> if you need help.',
                    ),
                }
            );

            $self->redirect_to('/');
        }
        catch ($e) {
            if ( $e =~ /human\-verification/i ) {
                $e =~ s/\s+at\s+(?:(?!\s+at\s+).)*[\r\n]*$//;
                $self->info('reCaptcha score too low');
                $self->stash( message => $e );
            }
            else {
                $e =~ s/\s+at\s+(?:(?!\s+at\s+).)*[\r\n]*$//;
                $self->stash( message => $e );
            }
        }
    }
}

sub reset_password ($self) {
    if ( my $passwd = $self->param('passwd') ) {
        try {
            if (
                QuizSage::Model::User->new->reset_password(
                    $self->stash('user_id'),
                    $self->stash('user_hash'),
                    $passwd,
                )
            ) {
                $self->info( 'Password reset for: ' . $self->stash('user_id') );
                $self->flash(
                    message => {
                        type => 'success',
                        text => 'Successfully reset password. Login with your new password.',
                    }
                );
                $self->redirect_to('/');
            }
            else {
                $self->stash( message => 'Failed to reset password.' );
            }
        }
        catch ($e) {
            $e =~ s/\s+at\s+(?:(?!\s+at\s+).)*[\r\n]*$//;
            $e =~ s/^"([^""]+)"/ '"' . join( ' ', map { ucfirst($_) } split( '_', $1 ) ) . '"' /e;
            $e =~ s/DBD::\w+::st execute failed:\s*//;
            $e .= '. Please try again.';

            $self->stash( message => $e );
        }
    }
}

sub login ($self) {
    try {
        $self->_recaptcha;

        my $user = QuizSage::Model::User->new->login( map { $self->param($_) } qw( email passwd ) );

        $self->info( 'Login success for: ' . $user->data->{email} );
        $self->session(
            user_id           => $user->id,
            last_request_time => time,
        );
    }
    catch ($e) {
        if ( $e =~ /human\-verification/i ) {
            $e =~ s/\s+at\s+(?:(?!\s+at\s+).)*[\r\n]*$//;
            $self->info('reCaptcha score too low');
            $self->flash( message => $e );
        }
        else {
            $self->info( 'Login failure for ' . $self->param('email') );
            $self->flash( message =>
                'Login failed. Please try again, or try the ' .
                '<a href="' . $self->url_for('/user/reset_password') . '">Reset Password page</a>.'
            );
        }
    }

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
        quiz_password     => undef,
    );

    $self->redirect_to('/');
}

sub _recaptcha ($self) {
    if ( my $recaptcha_secret_key = $self->app->conf->get( qw( recaptcha secret_key ) ) ) {
        my $site_verify = $self->ua->post(
            'https://www.google.com/recaptcha/api/siteverify',
            form => {
                secret   => $recaptcha_secret_key,
                response => $self->param('g-recaptcha-response'),
            },
        )->result->json;

        $self->info( 'Recaptcha site verify score: ' . ( $site_verify->{score} // '>>undef<<' ) );

        ( my $contact_email = conf->get( qw( email from ) ) )
            =~ s/(<|>)/ ( $1 eq '<' ) ? '&lt;' : '&gt;' /eg;

        die join( ' ',
            'Human-verification score too low.',
            'This may be due to a page load issue with your browser of choice.',
            'Try reloading the page, waiting for a minute, then resubmitting the form.',
            'If the problem persists, email <b>' . $contact_email . '</b> for help.',
        ) unless (
            $site_verify and
            $site_verify->{score} and
            $site_verify->{score} > $self->app->conf->get( qw( recaptcha min_score ) ) // 0.5
        );
    }

    return;
}

1;

=head1 NAME

QuizSage::Control::User

=head1 DESCRIPTION

This class is a subclass of L<Mojolicious::Controller> and provides handlers
for "user" actions.

=head1 METHODS

=head2 account

Handler for user create and user profile edit.

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
