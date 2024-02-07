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
        $self->param('roster_data') or
        $self->param('default_bible')
    ) {
        my $settings;

        my $quiz_defaults = $label->conf->get('quiz_defaults');
        my $user_defaults = $user->data->{settings}{pickup_quiz} // {};

        $settings->{$_} = $user_defaults->{$_} // $quiz_defaults->{$_} for ( qw( material roster_data ) );
        $settings->{default_bible} = $user_defaults->{default_bible} // $quiz_defaults->{bible};

        $self->stash(
            bibles => $label
                ->dq('material')
                ->get( 'bible', undef, undef, { order_by => 'acronym' } )
                ->run->all({}),
            label_aliases => $label->aliases,
            %$settings,
        );
    }
    else {
        my $settings = {
            maybe material      => $label->canonicalize( $self->param('material') ),
            maybe roster_data   => $self->param('roster_data'),
            maybe default_bible => $self->param('default_bible'),
        };

        $user->data->{settings}{pickup_quiz} = $settings;
        $user->save;

        my $quiz_id = QuizSage::Model::Quiz->new->pickup( $settings, $user->id )->id;
        $self->info('Pickup quiz generated: ' . $quiz_id );
        return $self->redirect_to( '/quiz/' . $quiz_id );
    }
}

sub teams ($self) {
    my $meet = QuizSage::Model::Meet->new->load( $self->param('meet') );
    return $self->redirect_to( '/meet/' . $self->param('meet') )
        unless ( $self->stash('user')->qm_auth($meet) );

    my $state  = $meet->state;
    my $teams  = [ map { $_->{name} } $state->{roster}->@* ];
    my ($quiz) =
        grep { $_->{name} eq $self->param('quiz') }
        map { map { $_->{rooms}->@* } $_->{sets}->@* }
        grep { $_->{name} eq $self->param('bracket') }
        $state->{brackets}->@*;

    unless ( $self->param('teams') ) {
        $self->stash(
            teams => $teams,
            quiz  => $quiz,
        );
    }
    else {
        my $roster = [
            map {
                my $name = $_;
                grep { $name eq $_ } map { $_->{name} } $state->{roster}->@*;
            }
            grep { /\S/ } map { s/(^\s+|\s+$)//gr }
            split( /\r?\n/, $self->param('teams') )
        ];

        if ( @$roster != $quiz->{roster}->@* ) {
            $self->info( 'Failed to parse teams: ' . $self->param('teams') );
            $self->flash( message => 'Teams seemingly not entered correctly. Try again.' );
            return $self->redirect_to(
                $self
                    ->url_for('/quiz/teams')
                    ->query( map { $_ => $self->param($_) } qw( bracket meet quiz ) )
            );
        }

        return $self->redirect_to(
            $self
                ->url_for('/quiz/build')
                ->query(
                    ( map { $_ => $self->param($_) } qw( bracket meet quiz ) ),
                    ( map { ( team => $_ ) } @$roster ),
                )
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
        $self->notice('Quiz build failed');
        $self->flash( message => 'Quiz settings creation failed' );
        return $self->redirect_to( '/meet/' . $self->param('meet') );
    }

    $settings->{teams} = [
        map {
            my $team_name = $_;
            grep { $_->{name} eq $team_name } $meet->data->{build}{roster}->@*
        } $self->every_param('team')->@*
    ];

    my $quiz_id = QuizSage::Model::Quiz->new->create({
        meet_id  => $meet->id,
        user_id  => $self->stash('user')->id,
        bracket  => $self->param('bracket'),
        name     => $self->param('quiz'),
        settings => $settings,
    })->id;

    $self->info( 'Quiz build: ' . $quiz_id );
    return $self->redirect_to( '/quiz/' . $quiz_id );
}

sub quiz ($self) {
    if ( ( $self->stash('format') // '' ) eq 'json' ) {
        $self->render( json => QuizSage::Model::Quiz->new->load( $self->param('quiz_id') )->data );
    }
    else {
        $self->stash( settings => QuizSage::Model::Quiz->new->load( $self->param('quiz_id') )->settings );
    }
}

sub save ($self) {
    my $success = 0;
    my $quiz    = QuizSage::Model::Quiz->new->load( $self->param('quiz_id') );

    if (
        $quiz->data->{user_id} and $quiz->data->{user_id} eq $self->stash('user')->id or
        $quiz->data->{meet_id} and
        $self->stash('user')->qm_auth( QuizSage::Model::Meet->new->load( $quiz->data->{meet_id} ) )
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

sub delete ($self) {
    my $quiz = QuizSage::Model::Quiz->new->load( $self->param('quiz_id') );

    if ( $self->stash('user')->qm_auth( $quiz->data->{meet_id} ) ) {
        $self->info( 'Quiz delete: ' . $quiz->id );
        $quiz->delete;
    }

    return $self->redirect_to( '/meet/' . $quiz->data->{meet_id} );
}

1;

=head1 NAME

QuizSage::Control::Quiz

=head1 DESCRIPTION

This class is a subclass of L<Mojolicious::Controller> and provides handlers
for "Main" actions.

=head1 METHODS

=head2 pickup

=head2 teams

=head2 build

=head2 quiz

=head2 save

=head2 delete

=head1 INHERITANCE

L<Mojolicious::Controller>.
