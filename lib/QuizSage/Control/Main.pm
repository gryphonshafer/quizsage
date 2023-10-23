package QuizSage::Control::Main;

use exact 'Mojolicious::Controller';
use QuizSage::Model::Quiz;

sub home ($self) {
    if ( $self->stash('user') ) {
        # $self->stash( active_quizzes => QuizSage::Model::Quiz->new->active_quizzes );
        $self->redirect_to('/quiz/settings');
    }
}

1;

=head1 NAME

QuizSage::Control::Main

=head1 DESCRIPTION

This class is a subclass of L<Mojolicious::Controller> and provides handlers
for "Main" actions.

=head1 METHODS

=head2 home

Handler for the home page.

=head1 INHERITANCE

L<Mojolicious::Controller>.
