package QuizSage::Control::Meet;

use exact 'Mojolicious::Controller';
use QuizSage::Model::Meet;

with 'Omniframe::Role::Bcrypt';

sub _load_meet ($self) {
    my $meet;
    try {
        $meet = QuizSage::Model::Meet->new->load( $self->param('meet_id') );
    }
    catch ($e) {
        $self->notice(
            'User ' . $self->stash('user')->id . ' requested missing meet ID ' . $self->param('meet_id')
        );
    }
    return $meet;
}

sub schedule ($self) {
    my $meet = $self->_load_meet or return $self->redirect_to('/');
    $self->stash(
        build   => $meet->data->{build},
        qm_auth => $self->stash('user')->qm_auth($meet),
    );
}

sub passwd ($self) {
    if ( my $meet_passwd = $self->param('meet_passwd') ) {
        $self->stash('user')->data->{settings}{meet_passwd} = $self->bcrypt($meet_passwd);
        $self->stash('user')->save;
        $self->redirect_to('/');
    }
}

sub roster ($self) {
    my $meet = $self->_load_meet or return $self->redirect_to('/');
    $self->stash( roster => $meet->data->{build}{roster} );
}

sub distribution ($self) {
    my $meet = $self->_load_meet or return $self->redirect_to('/');
    $self->stash( build => $meet->data->{build} );
}

1;

=head1 NAME

QuizSage::Control::Meet

=head1 DESCRIPTION

This class is a subclass of L<Mojolicious::Controller> and provides handlers
for "Meet" actions.

=head1 METHODS

=head2 schedule

=head2 passwd

=head2 roster

=head2 distribution

=head1 INHERITANCE

L<Mojolicious::Controller>.
