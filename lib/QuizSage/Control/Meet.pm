package QuizSage::Control::Meet;

use exact 'Mojolicious::Controller';
use QuizSage::Model::Meet;

with 'Omniframe::Role::Bcrypt';

sub passwd ($self) {
    if ( my $meet_passwd = $self->param('meet_passwd') ) {
        $self->stash('user')->data->{settings}{meet_passwd} = $self->bcrypt($meet_passwd);
        $self->stash('user')->save;
        $self->redirect_to('/');
    }
}

sub state ($self) {
    my $meet = QuizSage::Model::Meet->new->load( $self->param('meet_id') );
    $self->stash(
        state   => $meet->state,
        qm_auth => $self->stash('user')->qm_auth($meet),
    );
}

sub roster ($self) {
    $self->stash(
        roster => QuizSage::Model::Meet->new->load( $self->param('meet_id') )->data->{build}{roster},
    );
}

sub distribution ($self) {
    $self->stash(
        build => QuizSage::Model::Meet->new->load( $self->param('meet_id') )->data->{build},
    );
}

sub stats ($self) {
    $self->stash(
        stats => QuizSage::Model::Meet->new->load( $self->param('meet_id') )->stats,
    );
}

1;

=head1 NAME

QuizSage::Control::Meet

=head1 DESCRIPTION

This class is a subclass of L<Mojolicious::Controller> and provides handlers
for "Meet" actions.

=head1 METHODS

=head2 passwd

=head2 state

=head2 roster

=head2 distribution

=head2 stats

=head1 INHERITANCE

L<Mojolicious::Controller>.

=head1 WITH ROLE

L<Omniframe::Role::Bcrypt>.
