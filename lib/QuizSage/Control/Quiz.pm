package QuizSage::Control::Quiz;

use exact 'Mojolicious::Controller';
use QuizSage::Model::Label;
use QuizSage::Model::Meet;
use QuizSage::Model::Quiz;

sub practice ($self) {
    $self->stash( practice_label =>
        ( $self->param('practice_type') eq 'memory/memorize/setup' ) ? 'memorize'      :
        ( $self->param('practice_type') eq 'drill/setup'           ) ? 'queries_drill' :
        ( $self->param('practice_type') eq 'quiz/pickup/setup'     ) ? 'pickup_quiz'   : undef
    );

    my $user          = $self->stash('user');
    my $label         = QuizSage::Model::Label->new( user_id => $user->id );
    my $quiz_defaults = $label->conf->get('quiz_defaults');
    my $user_settings = $user->data->{settings}{ $self->stash('practice_label') }  // {};

    my $settings;
    $settings->{$_} = $self->param($_) // $user_settings->{$_} // $quiz_defaults->{$_}
        for (
            ( $self->stash('practice_label') eq 'pickup_quiz' )
                ? ( qw( bible roster_data material_label ) )
                : ('material_label')
        );

    unless ( $self->param('material_label') or $self->param('roster_data') ) {
        $self->stash(
            label_aliases => $label->aliases,
            bibles        => $label
                ->dq('material')
                ->get( 'bible', undef, undef, { order_by => 'acronym' } )
                ->run->all({}),
            %$settings,
        );
    }
    elsif (
        $self->stash('practice_label') eq 'memorize' or
        $self->stash('practice_label') eq 'queries_drill' or
        $self->stash('practice_label') eq 'pickup_quiz' and $self->param('generate_queries')
    ) {
        my $parsed_label = $label->parse( $settings->{material_label} );

        $settings->{material_label} .= ' ' . $settings->{bible}
            if ( not $parsed_label->{bibles} and $settings->{bible} );
        $settings->{material_label} = $label->canonicalize( $settings->{material_label} );

        $user->data->{settings}{ $self->stash('practice_label') } = $settings;
        $user->save;

        return $self->redirect_to(
            ( $self->stash('practice_label') eq 'memorize'      ) ? '/memory/memorize' :
            ( $self->stash('practice_label') eq 'queries_drill' ) ? '/drill'           :
            ( $self->stash('practice_label') eq 'pickup_quiz'   ) ? '/queries'         : '/'
        );
    }
    elsif ( $self->stash('practice_label') eq 'pickup_quiz' and not $self->param('generate_queries') ) {
        try {
            my $quiz_id = QuizSage::Model::Quiz->new->pickup( $settings, $user )->id;
            $self->info( 'Pickup quiz generated: ' . $quiz_id );
            return $self->redirect_to( '/quiz/pickup/' . $quiz_id );
        }
        catch ($e) {
            $self->info( 'Pickup quiz error: ' . $e );
            $self->flash( message => 'Pickup quiz settings error: ' . $e );
            return $self->redirect_to('/quiz/pickup/setup');
        }
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
            $self->flash( message => 'Teams seemingly not entered correctly' );
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

    my $quizzes = QuizSage::Model::Quiz->new->every_data({
        meet_id => $meet->id,
        bracket => $self->param('bracket'),
        name    => $self->param('quiz'),
    });
    return $self->redirect_to( '/quiz/' . $quizzes->[0]{quiz_id} ) if ( $quizzes and @$quizzes );

    unless ( $meet and $self->stash('user')->qm_auth($meet) ) {
        $self->flash( message => 'Unauthorized to build a quiz for this meet' );
        return $self->redirect_to( '/meet/' . $self->param('meet') );
    }

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
    my $quiz = QuizSage::Model::Quiz->new->load( $self->param('quiz_id') );

    if (
        not $quiz->data->{meet_id} and
        $quiz->data->{user_id} and $quiz->data->{user_id} ne $self->stash('user')->id
    ) {
        $self->flash( message => 'Unauthorized to view this particular quiz' );
        return $self->redirect_to('/');
    }
    else {
        $quiz->ensure_material_json_exists;

        unless ( ( $self->stash('format') // '' ) eq 'json' ) {
            $self->stash(
                quiz    => $quiz,
                meet_id => $quiz->data->{meet_id},
            );
        }
        else {
            my $data = $quiz->data;
            $data->{json_material_path} = $self->url_for( $quiz->conf->get( qw( material json path ) ) );
            $self->render( json => $data );
        }
    }
}

sub queries ($self) {
    my $quiz = QuizSage::Model::Quiz->new;

    unless ( ( $self->stash('format') // '' ) eq 'json' ) {
        $self->stash( quiz => $quiz );
        $self->stash( template => 'quiz/drill' ) if ( $self->stash('action_type') eq 'drill' );
    }
    else {
        my $quiz_defaults = $quiz->conf->get('quiz_defaults');
        my $user_settings = $self->stash('user')->data->{settings}{
            ( $self->stash('action_type') eq 'drill' ) ? 'queries_drill' : 'pickup_quiz'
        } // {};

        my $material_label = $user_settings->{material_label} // $quiz_defaults->{material_label};

        my $settings = {
            material => $quiz->create_material_json_from_label( $material_label, $self->stash('user') ),
        };

        if ( $self->stash('action_type') eq 'queries' ) {
            my $roster         = {
                maybe default_bible => $user_settings->{bible},
                data                => $user_settings->{roster_data},
            };

            QuizSage::Model::Meet->parse_and_structure_roster_text( \$roster );

            $settings->{teams} = $roster;
        }

        $self->render( json => {
            settings           => $settings,
            json_material_path => $self->url_for( $quiz->conf->get( qw( material json path ) ) ),
        } );
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
for "Quiz" actions.

=head1 METHODS

=head2 practice

This method handles setting up settings for pickup quizzes and query drills. In
both cases, the method uses user C<settings> (saved under C<pickup_quiz> and
C<queries_drill> respectively) and C<quiz_defaults> from the application
configuration (in that order of preference) to build a pickup quiz or query
drill.

L<QuizSage::Model::Quiz>'s C<pickup> is called to generate pickup quizzes.

=head2 teams

This method handles situations where in a meet a quiz magistrate wants to
manually set a quiz's teams prior to those teams being automatically assigned
based on a meet's C<settings>/C<build> and the results of other quizzes. As
such, it's unlikely a quiz magistrate should need to leverage this
method/handler; it exists as a failsafe.

The handler requires a user be "quiz magistrate authorized" as defined by
L<QuizSage::Model::User>'s C<qm_auth>.

The handler will render data for the quiz magistrate including a list of teams
and quiz information. And upon form submit, the method will build the quiz with
the teams submitted.

=head2 build

This handler will build a quiz for a meet, then it'll redirect to the quiz's
display page. The handler requires a user be "quiz magistrate authorized"
as defined by L<QuizSage::Model::User>'s C<qm_auth>.

=head2 quiz

This handler runs quizzes (both meet and pickup). It will ensure that the quiz's
material JSON exists via a call to L<QuizSage::Model::Quiz>'s
C<ensure_material_json_exists>. It will then, if not requesting JSON, load the
quiz object into the C<quiz> stash value; and if requesting JSON, it will
provide quiz data as JSON (along with an added C<json_material_path> key/value).

The method requires a C<quiz_id> parameter to identify the quiz to provide.

=head2 queries

This method handles running query drills and displaying a quiz's worth of
queries (potentially to print).

If not requesting JSON, the handler will load the C<quiz> stash value with a
blank quiz object. Otherwise, the handler return a JSON consisting of
C<settings> and C<json_material_path> key/values, which is sufficient for the
Javascript application to run as desired.

=head2 save

This method handles saving quiz C<state>, which should happen after every quiz
event. The handler requires a user be "quiz magistrate authorized" as defined by
L<QuizSage::Model::User>'s C<qm_auth>.

The method requires a C<quiz_id> parameter to identify the quiz, and it expects
JSON data to be POSTed.

=head2 delete

This method handles situations where in a meet a quiz magistrate wants to
delete quiz. It's unlikely a quiz magistrate should need to leverage this
method/handler; it exists as a failsafe.

The method requires a C<quiz_id> parameter value to identify the quiz to delete.

The handler requires a user be "quiz magistrate authorized" as defined by
L<QuizSage::Model::User>'s C<qm_auth>.

=head1 INHERITANCE

L<Mojolicious::Controller>.
