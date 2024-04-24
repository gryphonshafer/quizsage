package QuizSage::Control::Memory;

use exact 'Mojolicious::Controller';
use QuizSage::Model::Memory;

sub memorize ($self) {
    my $memory = QuizSage::Model::Memory->new;

    unless ( $self->req->json ) {
        $self->stash( to_memorize => $memory->to_memorize( $self->stash('user') ) );
    }
    else {
        my $data = $self->req->json;
        $data->{user_id} = $self->stash('user')->id,
        $memory->memorized($data);
        $self->render( json => { memorize_saved => 1 } );
    }
}

sub review ($self) {
    my $memory = QuizSage::Model::Memory->new;

    $memory->reviewed(
        $self->param('memory_id'),
        $self->param('level'),
        $self->stash('user')->id,
    ) if ( $self->param('memory_id') and $self->param('level') );

    $self->stash( verse => $memory->review_verse( $self->stash('user') ) );
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
