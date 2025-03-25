package QuizSage::Control::Flag;

use exact 'Mojolicious::Controller';
use QuizSage::Model::Flag;

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
        is_app_admin => $self->stash('user')->is_app_admin,
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
            if ( $self->stash('user')->is_app_admin );
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

sub is_app_admin ($self) {
    return unless ( $self->stash('user')->is_app_admin );

    if ( $self->param('is_app_admin') ) {
        $self->stash('user')->dq
            ->sql('INSERT INTO administrator (user_id) VALUES (?)')
            ->run( $self->param('user_id') );
    }
    else {
        $self->stash('user')->dq
            ->sql('DELETE FROM administrator WHERE user_id = ? AND season_id IS NULL and meet_id IS NULL')
            ->run( $self->param('user_id') );
    }

    $self->render( json => $self->req->params->to_hash );
}

sub administrators ($self) {
    $self->redirect_to('/flag/list') unless ( $self->stash('user')->is_app_admin );

    $self->stash(
        users => [
            sort {
                $b->{is_app_admin} <=> $a->{is_app_admin} or
                $a->{first_name} cmp $b->{first_name} or
                $a->{last_name} cmp $b->{last_name}
            }
            map {
                $_->{is_app_admin} = $self->stash('user')->is_app_admin( $_->{user_id} );
                $_;
            } $self->stash('user')->every_data
        ],
    );
}

sub thesaurus ($self) {
    $self->redirect_to('/flag/list') unless ( $self->stash('user')->is_app_admin );

    if ( $self->param('yaml') ) {
        my $error;
        try {
            QuizSage::Model::Flag->new->thesaurus_patch(
                $self->param('yaml'),
                $self->stash('user'),
            );
        }
        catch ($e) {
            $error = $e;
        }

        $self->flash(
            memo => ($error)
                ? {
                    class   => 'error',
                    message => 'Thesaurus failed to be patched: ' . deat $error,
                }
                : {
                    class   => 'success',
                    message => 'Thesaurus successfully patched',
                }
        );

        $self->redirect_to('/flag/thesaurus');
    }
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

=head2 is_app_admin

This controller handles user application administrator checkbox checking and
unchecking on the flag list page.

=head2 administrators

This controller handles display of the user list and checkboxes for application
administrator.

=head2 thesaurus

This controller handles display of the thesaurus modification page.

=head1 INHERITANCE

L<Mojolicious::Controller>.
