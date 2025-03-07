package QuizSage::Control::Api::Season;

use exact 'Mojolicious::Controller';
use QuizSage::Model::Season;
use QuizSage::Model::Meet;

sub list ($self) {
    $self->openapi->valid_input or return;
    $self->render( openapi => QuizSage::Model::Season->new->seasons );
}

sub meets ($self) {
    $self->openapi->valid_input or return;
    my $every_data;
    if (
        $every_data = QuizSage::Model::Meet->new->every_data({
            season_id => $self->param('season_id'),
            hidden    => 0,
        })
    ) {
        for (@$every_data) {
            delete $_->{build};
            delete $_->{hidden};
            delete $_->{passwd};
            delete $_->{settings};
            delete $_->{stats};
        }
    }
    $self->render( openapi => ( $every_data and @$every_data ) ? $every_data : undef );
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

=head2 meets

This endpoint returns a given season's meets.

=head2 stats

This endpoint provides the C<stats> data of a L<QuizSage::Model::Season> object.

=head1 INHERITANCE

L<Mojolicious::Controller>.
