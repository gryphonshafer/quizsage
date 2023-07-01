package QuizSage::Control::Main;

use exact 'Mojolicious::Controller';
use QuizSage::Model::Quiz;

sub home ($self) {
    if ( $self->stash('user') ) {
        $self->stash( active_quizzes => QuizSage::Model::Quiz->new->active_quizzes );
    }
}

sub quiz_password ($self) {
    $self->session( quiz_password => $self->param('passwd') );
    return $self->redirect_to('/');
}

sub quiz ($self) {
    my $quiz = QuizSage::Model::Quiz->new->load( $self->param('id') );

    my $message = (
        $quiz->data->{password} and
        $self->session('quiz_password') and
        $quiz->data->{password} ne $self->session('quiz_password')
    ) ? q{
        This quiz requires a password to write data, and the quiz password you provided doesn't match.
        If you're not the official QM, you can ignore this warning.
        Otherwise, you'll need to log out and back in again.
    } : undef;

    unless (
        $quiz->data->{settings}{teams} and
        grep { $_->{name} and not ref $_->{name} } $quiz->data->{settings}{teams}->@*
    ) {
        $self->flash( message => $message );
        return $self->redirect_to( '/quiz/settings/' . $self->param('id') );
    }

    $self->stash(
        quiz    => $quiz,
        message => $message,
    );
}

sub quiz_settings ($self) {
    if ( $self->param('teams') ) {
        my $quiz = QuizSage::Model::Quiz->new->load( $self->stash('quiz_id') );

        my $submitted_teams = [
            grep { length }
            map { s/(?:^\s+|\s+$)//g; $_ }
            split( /\r?\n/, $self->param('teams') )
        ];

        my $actual_teams = $quiz->dq
            ->sql('SELECT DISTINCT team FROM registration WHERE meet_id = ?')
            ->run( $quiz->data->{meet_id} )->column;

        my @teams = map {
            my $team = $_;
            grep { lc $team eq lc $_ } @$actual_teams;
        } @$submitted_teams;

        if ( @teams == 3 ) {
            $quiz->data->{settings} = { $quiz->data->{settings}->%* };
            $quiz->data->{settings}{teams} = \@teams;
            $quiz->save;

            return $self->redirect_to( '/quiz?id=' . $self->stash('quiz_id') );
        }
    }
}

sub quiz_data ($self) {
    $self->render( json => QuizSage::Model::Quiz->new->load( $self->stash('quiz_id') )->data );
}

sub save_quiz_data ($self) {
    my $quiz = QuizSage::Model::Quiz->new->load( $self->stash('quiz_id') );

    my $success = 0;
    if (
        not $quiz->data->{password} or
        $self->session('quiz_password') and $quiz->data->{password} eq $self->session('quiz_password')
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

QuizSage::Control::Main

=head1 DESCRIPTION

This class is a subclass of L<Mojolicious::Controller> and provides handlers
for "Main" actions.

=head1 METHODS

=head2 home

Handler for the home page.

=head2 quiz

Handler for the quiz page.

=head1 INHERITANCE

L<Mojolicious::Controller>.
