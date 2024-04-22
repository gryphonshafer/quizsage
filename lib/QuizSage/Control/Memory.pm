package QuizSage::Control::Memory;

use exact 'Mojolicious::Controller';

sub memorize ($self) {
    $self->warn('memorize');
}

sub review ($self) {
    $self->warn('review');
}

sub state ($self) {
    $self->warn('state');
}

1;

=head1 NAME

QuizSage::Control::Memory

=head1 DESCRIPTION

This class is a subclass of L<Mojolicious::Controller> and provides handlers
for "Memory" actions.

=head1 METHODS

=head2 memorize

This controller handles C<memorize> display.

=head2 review

This controller handles C<review> display.

=head2 state

This controller handles C<state> display.

=head1 INHERITANCE

L<Mojolicious::Controller>.
