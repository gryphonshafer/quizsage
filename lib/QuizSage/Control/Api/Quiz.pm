package QuizSage::Control::Api::Quiz;

use exact 'Mojolicious::Controller';
use QuizSage::Model::Quiz;

sub data ($self) {
    $self->openapi->valid_input or return;
    my $data;
    try {
        $data = QuizSage::Model::Quiz->new->load( $self->param('quiz_id') )->data;
    }
    catch ($e) {}
    $self->render( openapi => $data );
}

1;

=head1 NAME

QuizSage::Control::Api::Quiz

=head1 DESCRIPTION

This class is a subclass of L<Mojolicious::Controller> and provides handlers
for "Quizzes" API calls.

=head1 METHODS

=head2 data

Given a quiz ID, this endpoint will return the quiz data (assuming that quiz
exists).

=head1 INHERITANCE

L<Mojolicious::Controller>.
