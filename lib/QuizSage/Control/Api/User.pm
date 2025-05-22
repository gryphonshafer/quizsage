package QuizSage::Control::Api::User;

use exact 'Mojolicious::Controller';
use QuizSage::Model::User;

sub login ($self) {
    $self->openapi->valid_input or return;
    my $response;

    try {
        my $user = QuizSage::Model::User->new->login(
            map { $self->req->body_params->param($_) } qw( email password )
        );

        $response->{message} = 'Login success for: ' . $user->data->{email};
        $response->{success} = 1;

        $self->info( $response->{message} );
        $self->session( user_id => $user->id );

        $self->render( openapi => $response );
    }
    catch ($e) {
        $response->{message} = 'Login failure for ' . $self->param('email');
        $response->{success} = 0;

        $self->notice( $response->{message} );
        $self->render( status => 401, openapi => $response );
    }
}

sub logout ($self) {
    $self->openapi->valid_input or return;
    $self->session( user_id => undef );
    $self->render( openapi => {
        success => 1,
        message => 'Logout successful',
    } );
}

1;

=head1 NAME

QuizSage::Control::Api::User

=head1 DESCRIPTION

This class is a subclass of L<Mojolicious::Controller> and provides handlers
for "User Accounts" API calls.

=head1 METHODS

=head2 login

Handler for login. If logic is successful, the session will be updated with a
C<user_id> field and a C<last_request_time> field, which L<QuizSage::Control>
uses for login/user setup per request as needed.

=head2 logout

Handler for logout. Deletes the session value C<user_id>.

=head1 INHERITANCE

L<Mojolicious::Controller>.
