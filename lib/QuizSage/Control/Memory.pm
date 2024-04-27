package QuizSage::Control::Memory;

use exact 'Mojolicious::Controller';
use QuizSage::Model::Memory;
use QuizSage::Model::User;
use Mojo::JSON 'decode_json';

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
    unless ( ( $self->stash('format') // '' ) eq 'json' ) {
        my $memory = QuizSage::Model::Memory->new;

        if ( $self->param('user_id') ) {
            $memory->sharing({
                action            => $self->param('action'),
                memorizer_user_id => $self->stash('user')->id,
                shared_user_id    => $self->param('user_id'),
            });
            return $self->redirect_to('/memory/state');
        }
        elsif ( $self->param('shared_from_labels') ) {
            my ( %bibles, @names, @refs );
            for my $label ( map { decode_json($_) } $self->every_param('label')->@* ) {
                push( @names, $label->{name} );
                for my $block ( $label->{blocks}->@* ) {
                    $bibles{ $block->{bible} };
                    push( @refs, $block->{refs} );
                }
            }

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
                    label  => join( ' ',
                        QuizSage::Model::Memory->new->bible_ref
                            ->acronyms(0)->sorting(1)->add_detail(0)
                            ->clear->in(@refs)->refs,
                        sort keys %bibles,
                    ),
                )
            );
        }
        $self->stash( state => $memory->state( $self->stash('user') ) );
    }
    else {
        $self->render( json => QuizSage::Model::User->new->by_full_name( $self->param('name') ) );
    }
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
