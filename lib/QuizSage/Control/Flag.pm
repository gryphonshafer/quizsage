package QuizSage::Control::Flag;

use exact 'Mojolicious::Controller';
use QuizSage::Model::Flag;
use QuizSage::Model::User;

sub add ($self) {
    my $flag = QuizSage::Model::Flag->new;
    my $body = $self->req->json;

    $self->render( json => {
        flag_id => $flag->create({
            user_id => $self->stash('user')->id,
            source  => delete $body->{source},
            url     => delete $body->{url},
            report  => delete $body->{report},
            data    => $body->{data},
        })->id
    } );
}

sub list ($self) {
    $self->stash(
        template     => 'flag/list',
        flags        => QuizSage::Model::Flag->new->list,
        is_app_admin => QuizSage::Model::User->new->is_app_admin( $self->stash('user')->id ),
    );
}

sub item ($self) {
    my $json;
    try {
        $json = QuizSage::Model::Flag->new->load( $self->param('flag_id') )->data->{data};
    }
    catch ($e) {
        $json = { error => 'Unable to locate flag' };
    }
    $self->render( json => $json );
}

sub remove ($self) {
    try {
        QuizSage::Model::Flag->new->load( $self->param('flag_id') )->delete
            if ( QuizSage::Model::User->new->is_app_admin( $self->stash('user')->id ) );
    }
    catch ($e) {
        $self->flash(
            memo => {
                class   => 'error',
                message => 'Failed to delete the flag',
            }
        );
    }

    $self->redirect_to('/flag/list');
}

1;

=head1 NAME

QuizSage::Control::Flag

=head1 DESCRIPTION

This class is a subclass of L<Mojolicious::Controller> and provides handlers
for "Flag" actions.

=head1 METHODS

=head2 add

This controller handles addition of a flag item to the set of flags.

=head2 list

This controller handles listing of flags.

=head2 item

This controller handles returning the JSON data of a flag.

=head2 remove

This controller handles removing a flag.

=head1 INHERITANCE

L<Mojolicious::Controller>.
