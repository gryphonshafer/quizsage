package QuizSage::Control::Quiz;

use exact 'Mojolicious::Controller';
use QuizSage::Model::Meet;
use QuizSage::Model::Quiz;

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

=head2 build

=head2 quiz

=head1 INHERITANCE

L<Mojolicious::Controller>.
