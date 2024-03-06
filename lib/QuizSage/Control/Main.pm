package QuizSage::Control::Main;

use exact 'Mojolicious::Controller';
use QuizSage::Model::Season;

sub home ($self) {
    $self->stash( active_seasons => QuizSage::Model::Season->new->active_seasons )
        if ( $self->stash('user') );
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

=head1 INHERITANCE

L<Mojolicious::Controller>.
