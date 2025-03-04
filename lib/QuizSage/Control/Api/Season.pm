package QuizSage::Control::Api::Season;

use exact 'Mojolicious::Controller';
use QuizSage::Model::Season;

sub list ($self) {
    $self->openapi->valid_input or return;
    $self->render( openapi => QuizSage::Model::Season->new->seasons );
}

sub stats ($self) {
    $self->openapi->valid_input or return;
    my $stats;
    try {
        $stats = QuizSage::Model::Season->new->load( $self->param('season_id') )->data->{stats};
    }
    catch ($e) {}
    $self->render( openapi => ( $stats and %$stats ) ? $stats : undef );
}

1;

=head1 NAME

QuizSage::Control::Api::Season

=head1 DESCRIPTION

This class is a subclass of L<Mojolicious::Controller> and provides handlers
for "Quiz Seasons" API calls.

=head1 METHODS

=head2 list

This endpoint wraps the L<QuizSage::Model::Season> C<seasons> method.

=head2 stats

This endpoint provides the C<stats> data of a L<QuizSage::Model::Season> object.

=head1 INHERITANCE

L<Mojolicious::Controller>.
