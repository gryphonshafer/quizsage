package QuizSage::Control::Memory;

use exact 'Mojolicious::Controller';
use QuizSage::Model::Memory;
use QuizSage::Model::User;
use Mojo::JSON 'decode_json';

sub memorize ($self) {
    my $memory = QuizSage::Model::Memory->new;
    my $user   = ( $self->session('become') )
        ? QuizSage::Model::User->new->load( $self->session('become') )
        : $self->stash('user');

    unless ( $self->req->json ) {
        $self->stash(
            to_memorize => $memory->to_memorize($user),
            user        => $user,
        );
    }
    else {
        my $data = $self->req->json;
        $data->{user_id} = $user->id,
        $memory->memorized($data);
        $self->render( json => { memorize_saved => 1 } );
    }
}

sub review ($self) {
    my $memory = QuizSage::Model::Memory->new;
    my $user   = ( $self->session('become') )
        ? QuizSage::Model::User->new->load( $self->session('become') )
        : $self->stash('user');

    $memory->reviewed(
        $self->param('memory_id'),
        $self->param('level'),
        $user->id,
    ) if ( $self->param('memory_id') and $self->param('level') );

    $self->stash(
        verse => $memory->review_verse($user),
        user  => $user,
    );
}

sub state ($self) {
    my $memory = QuizSage::Model::Memory->new;

    if ( ( $self->param('action') // '' ) eq 'become' ) {
        my ($shared_from_user) =
            grep { $_->{user_id} == $self->param('user_id') }
            $memory->shared_from_users( $self->stash('user') )->@*;

        if ($shared_from_user) {
            $self->session( become => $self->param('user_id') );
            $self->flash( message => {
                type => 'success',
                text => join( ' ',
                    q{You have temporarily "become"},
                    $shared_from_user->{first_name},
                    $shared_from_user->{last_name},
                    q{for the purpose of updating that account's memorization.},
                ),
            } );
            return $self->redirect_to('/memory/memorize/setup');
        }
    }
    elsif ( ( $self->param('action') // '' ) eq 'unbecome' ) {
        if ( $self->session('become') ) {
            $self->session( become => undef );
            $self->flash( message => {
                type => 'success',
                text => 'You have reverted to your own user account.',
            } );
        }
        return $self->redirect_to('/memory/state');
    }
    elsif ( ( $self->param('action') // '' ) eq 'unfollow' ) {
        $memory->sharing({
            action            => 'remove',
            memorizer_user_id => $self->param('user_id'),
            shared_user_id    => $self->stash('user')->id,
        });
        return $self->redirect_to('/memory/state');
    }
    elsif ( $self->param('user_id') ) {
        $memory->sharing({
            action            => $self->param('action'),
            memorizer_user_id => $self->stash('user')->id,
            shared_user_id    => $self->param('user_id'),
        });
        return $self->redirect_to('/memory/state');
    }
    elsif ( $self->param('shared_from_labels') ) {
        my @persons = map { decode_json($_) } $self->every_param('persons')->@*;

        my @names = map { $_->{name} } @persons;
        @names = map { $_->[0] } sort { $a->[1] <=> $b->[1] } map { [ $_, rand ] } @names;
        my @teams;
        if ( @names > 2 and @names % 3 == 1 ) {
            @teams = (
                [ shift @names, shift @names ],
                [ shift @names, shift @names ],
            );
        }
        elsif ( @names > 2 and @names % 3 == 2 ) {
            @teams = (
                [ shift @names, shift @names, shift @names ],
                [ shift @names, shift @names ],
            );
        }
        push( @teams, [ grep { defined } shift @names, shift @names, shift @names ] ) while (@names);
        @teams = map { $_->[0] } sort { $a->[1] <=> $b->[1] } map { [ $_, rand ] } @teams;

        my $team_number;
        return $self->redirect_to(
            $self->url_for('/quiz/pickup/setup')->query(
                roster => join( "\n\n", map { join( "\n", 'Team ' . ++$team_number, @$_ ) } @teams ),
                label  => $memory->shared_labels(
                    $self->stash('user')->id,
                    [ map { $_->{id} } @persons ],
                ),
            )
        );
    }

    $self->stash( state => $memory->state( $self->stash('user') ) );
}

1;

=head1 NAME

QuizSage::Control::Memory

=head1 DESCRIPTION

This class is a subclass of L<Mojolicious::Controller> and provides handlers
for "Memory" actions.

=head1 METHODS

=head2 memorize

This controller handles the initial memorization page by setting the
C<to_memorize> stash value based on L<QuizSage::Model::Memory>'s C<to_memorize>.
It will also handle memorized verse save actions via JSON POST.

=head2 review

This controller handles the memorization review page by setting the
C<verse> stash value based on L<QuizSage::Model::Memory>'s C<review_verse>.

=head2 state

This controller handles the memorization state page by setting the C<state>
stash value based on L<QuizSage::Model::Memory>'s C<state>.

It also handles a variety of other calls coming off the memorization state page.

=head1 INHERITANCE

L<Mojolicious::Controller>.
