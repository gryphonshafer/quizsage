package QuizSage::Control::Api::Meet;

use exact 'Mojolicious::Controller';
use QuizSage::Model::Meet;
use QuizSage::Model::Quiz;

sub quizzes ($self) {
    $self->openapi->valid_input or return;
    my $every_data = QuizSage::Model::Quiz->new->every_data({ meet_id => $self->param('meet_id') });
    $self->render( openapi => ( $every_data and @$every_data ) ? $every_data : undef );
}

sub state ($self) {
    $self->openapi->valid_input or return;
    my $state;
    try {
        $state = QuizSage::Model::Meet->new->load( $self->param('meet_id') )->state;
    }
    catch ($e) {}
    $self->render( openapi => $state );
}

sub stats ($self) {
    $self->openapi->valid_input or return;
    my $stats;
    try {
        $stats = QuizSage::Model::Meet->new->load( $self->param('meet_id') )->data->{stats};
    }
    catch ($e) {}
    $self->render( openapi => ( $stats and %$stats ) ? $stats : undef );
}

1;

=head1 NAME

QuizSage::Control::Api::Meet

=head1 DESCRIPTION

This class is a subclass of L<Mojolicious::Controller> and provides handlers
for "Quiz Meets" API calls.

=head1 METHODS

=head2 quizzes

Given a meet ID, this endpoint will return all created quiz records (quizzes
that have at least been started).

=head2 state

This endpoint wraps the L<QuizSage::Model::Meet> C<state> method.

=head2 stats

This endpoint provides the C<stats> data of a L<QuizSage::Model::Meet> object.

=head1 INHERITANCE

L<Mojolicious::Controller>.
