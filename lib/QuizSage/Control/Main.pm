package QuizSage::Control::Main;

use exact 'Mojolicious::Controller';
use QuizSage::Model::Season;

sub home ($self) {
    $self->stash( active_seasons => QuizSage::Model::Season->new->active_seasons )
        if ( $self->stash('user') );
}

sub set ($self) {
    $self->session( $self->param('type') => $self->param('name') );

    if ( my $user = $self->stash('user') ) {
        $user->data->{settings}{ $self->param('type') } = $self->param('name');
        $user->save;
    }

    $self->redirect_to( $self->req->headers->referer );
}

1;

=head1 NAME

QuizSage::Control::Main

=head1 DESCRIPTION

This class is a subclass of L<Mojolicious::Controller> and provides handlers
for "Main" actions.

=head1 METHODS

=head2 home

Handler for the home page. The home page has a not-logged-in view and a
logged-in view that are substantially different.

=head2 set

This handler will set the C<type>-parameter-named session value to the C<name>
parameter value. If the user is logged in, this handler will also save the
the C<name> parameter value to the user's settings JSON under the
C<type>-parameter-named name. Finally, this handler will redirect back to the
referer.

=head1 INHERITANCE

L<Mojolicious::Controller>.
