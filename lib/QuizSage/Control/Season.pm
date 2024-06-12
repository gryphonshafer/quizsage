package QuizSage::Control::Season;

use exact 'Mojolicious::Controller';
use QuizSage::Model::Season;

sub stats ($self) {
    my $season = QuizSage::Model::Season->new->load( $self->param('season_id') );
    $self->stash(
        stats  => $season->stats,
        season => $season,
    );
}

1;

=head1 NAME

QuizSage::Control::Season

=head1 DESCRIPTION

This class is a subclass of L<Mojolicious::Controller> and provides handlers
for "Season" actions.

=head1 METHODS

=head2 stats

This controller handles meet statistics display by setting the C<stats> stash
value based on L<QuizSage::Model::Season>'s C<stats>.

=head1 INHERITANCE

L<Mojolicious::Controller>.
