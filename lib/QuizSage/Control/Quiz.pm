package QuizSage::Control::Quiz;

use exact 'Mojolicious::Controller';
use QuizSage::Model::Label;
use QuizSage::Model::Meet;
use QuizSage::Model::Quiz;

sub pickup ($self) {
    my $user  = $self->stash('user');
    my $label = QuizSage::Model::Label->new( user_id => $user->id );

    unless (
        $self->param('material') or
        $self->param('default_bible') or
        $self->param('roster_data')
    ) {
        my $settings = $user->data->{settings}{pickup_quiz} // {};

        $settings->{material}      //= $label->conf->get('default_material'),
        $settings->{default_bible} //= $label->conf->get('default_bible');
        $settings->{roster_data}   //= join( "\n\n", map { join( "\n", @$_ ) }
            [ 'Team 1', 'Alpha Bravo',   'Charlie Delta', 'Echo Foxtrox' ],
            [ 'Team 2', 'Gulf Hotel',    'India Juliet',  'Kilo Lima'    ],
            [ 'Team 3', 'Mike November', 'Oscar Papa',    'Romeo Quebec' ],
        );

        $self->stash(
            label_aliases => $label->aliases,
            %$settings,
        );
    }
    else {
        my $settings = {
            material      => $label->canonicalize( $self->param('material') ),
            default_bible => $self->param('default_bible') || $label->conf->get('default_bible'),
            roster_data   => $self->param('roster_data'),
        };

        $user->data->{settings}{pickup_quiz} = $settings;
        $user->save;

        return $self->redirect_to(
            '/quiz/' . QuizSage::Model::Quiz->new->pickup( $settings, $user->id )->id
        );
    }
}

sub build ($self) {
    my $meet = QuizSage::Model::Meet->new->load( $self->param('meet') );

    unless ( $meet and $self->stash('user')->qm_auth($meet) ) {
        $self->flash( message => 'Unauthorized to build a quiz for this meet' );
        return $self->redirect_to( '/meet/' . $self->param('meet') );
    }

    my $quizzes = QuizSage::Model::Quiz->new->every_data({
        meet_id => $meet->id,
        bracket => $self->param('bracket'),
        name    => $self->param('quiz'),
    });
    return $self->redirect_to( '/quiz/' . $quizzes->[0]{quiz_id} ) if ( $quizzes and @$quizzes );

    my $settings = $meet->quiz_settings( $self->param('bracket'), $self->param('quiz') );
    unless ($settings) {
        $self->flash( message => 'Quiz settings creation failed' );
        return $self->redirect_to( '/meet/' . $self->param('meet') );
    }

    my $quiz = QuizSage::Model::Quiz->new->create({
        meet_id  => $meet->id,
        user_id  => $self->stash('user')->id,
        bracket  => $self->param('bracket'),
        name     => $self->param('quiz'),
        settings => $settings,
    });

    return $self->redirect_to( '/quiz/' . $quiz->id );
}

sub quiz ($self) {
    if ( ( $self->stash('format') // '' ) eq 'json' ) {
        $self->render( json => QuizSage::Model::Quiz->new->load( $self->param('quiz_id') )->data );
    }
    else {
        $self->stash( quiz => QuizSage::Model::Quiz->new->load( $self->param('quiz_id') ) );
    }
}

sub save ($self) {
    my $success = 0;
    my $quiz    = QuizSage::Model::Quiz->new->load( $self->param('quiz_id') );

    unless (
        not $quiz->data->{meet_id} and $quiz->data->{meet_id} ne $self->stash('user')->id or
        not $self->stash('user')->qm_auth( QuizSage::Model::Meet->new->load( $quiz->data->{meet_id} ) )
    ) {
        $quiz->save({ state => $self->req->json });
        $success = 1;
    }

    $self->info(
        'Save quiz data ' .
        ( ($success) ? 'success' : 'failure' ) .
        ' for quiz ID: ' . $self->stash('quiz_id')
    );

    $self->render( json => { quiz_data_saved => $success } );
}

1;

=head1 NAME

QuizSage::Control::Quiz

=head1 DESCRIPTION

This class is a subclass of L<Mojolicious::Controller> and provides handlers
for "Main" actions.

=head1 METHODS

=head2 pickup

=head2 build

=head2 quiz

=head2 save

=head1 INHERITANCE

L<Mojolicious::Controller>.
