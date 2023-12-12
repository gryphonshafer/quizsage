package QuizSage::Control::Main;

use exact 'Mojolicious::Controller';
use QuizSage::Model::Season;
use QuizSage::Model::Meet;

with 'Omniframe::Role::Bcrypt';

sub home ($self) {
    if ( $self->stash('user') ) {
        $self->stash( active_seasons => QuizSage::Model::Season->new->active_seasons );
    }
}

sub meet ($self) {
    try {
        $self->stash( schedule => QuizSage::Model::Meet->new->load( $self->param('meet_id') )->schedule );
    }
    catch ($e) {
        $self->notice(
            'User ' . $self->stash('user')->id . ' requested missing meet ID ' . $self->param('meet_id')
        );
        $self->redirect_to('/');
    }
}

sub qm_auth ($self) {
    if ( my $qm_auth = $self->param('qm_auth') ) {
        $self->stash('user')->{data}{settings}{qm_auth} =  $self->bcrypt($qm_auth);
        $self->stash('user')->save;
        $self->redirect_to('/');
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
