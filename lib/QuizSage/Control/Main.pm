package QuizSage::Control::Main;

use exact 'Mojolicious::Controller';
use QuizSage::Model::Quiz;
use QuizSage::Util::Material 'material_json';
use Bible::Reference;

sub home ($self) {
    if ( $self->stash('user') ) {
        # $self->stash( active_quizzes => QuizSage::Model::Quiz->new->active_quizzes );
        return $self->redirect_to('/quiz/settings');
    }
}

sub quiz_password ($self) {
    $self->session( quiz_password => $self->param('passwd') );
    return $self->redirect_to('/');
}

sub quiz ($self) {
    my $quiz = QuizSage::Model::Quiz->new->load( $self->param('id') );

    # my $message = (
    #     $quiz->data->{password} and
    #     $self->session('quiz_password') and
    #     $quiz->data->{password} ne $self->session('quiz_password')
    # ) ? q{
    #     This quiz requires a password to write data, and the quiz password you provided doesn't match.
    #     If you're not the official QM, you can ignore this warning.
    #     Otherwise, you'll need to log out and back in again.
    # } : undef;

    # unless (
    #     $quiz->data->{settings}{teams} and
    #     grep { $_->{name} and not ref $_->{name} } $quiz->data->{settings}{teams}->@*
    # ) {
    #     $self->flash( message => $message );
    #     return $self->redirect_to( '/quiz/settings/' . $self->param('id') );
    # }

    $self->stash(
        quiz    => $quiz,
        # message => $message,
    );
}

sub quiz_settings ($self) {
    if (
        defined $self->param('teams') and
        defined $self->param('ranges') and
        defined $self->param('translations') and
        defined $self->param('club_100') and
        defined $self->param('club_250') and
        defined $self->param('full_material')
    ) {
        my $club_100_matrix = [
            [ 'Ep 1',  [ 3, 7, 11, 13, 18           ] ],
            [ 'Ep 2',  [ 6, 8, 10, 19, 22           ] ],
            [ 'Ep 3',  [ 6, 10, 16, 20, 21          ] ],
            [ 'Ep 4',  [ 3, 16, 25, 29, 32          ] ],
            [ 'Ep 5',  [ 3, 8, 15, 19               ] ],
            [ 'Ep 6',  [ 11, 12, 13, 14, 15, 16, 17 ] ],
            [ 'Ga 1',  [ 6, 8, 15, 16               ] ],
            [ 'Ga 2',  [ 16, 17, 19, 20             ] ],
            [ 'Ga 3',  [ 7, 11, 14, 24, 26, 28      ] ],
            [ 'Ga 4',  [ 4, 5, 9                    ] ],
            [ 'Ga 5',  [ 1, 5, 13, 14, 22, 23       ] ],
            [ 'Ga 6',  [ 1, 2, 4, 7, 9, 10, 14      ] ],
            [ 'Php 1', [ 6, 21, 27, 29              ] ],
            [ 'Php 2', [ 3, 8, 10, 13, 14, 15       ] ],
            [ 'Php 3', [ 8, 10, 12, 14, 20          ] ],
            [ 'Php 4', [ 4, 6, 7, 8, 19             ] ],
            [ 'Cl 1',  [ 10, 15, 16, 22, 27         ] ],
            [ 'Cl 2',  [ 6, 8, 9, 13, 20            ] ],
            [ 'Cl 3',  [ 1, 5, 11, 12, 15, 17       ] ],
            [ 'Cl 4',  [ 2, 5, 6                    ] ],
        ];

        my $club_250_matrix = [
            [ 'Ep 1',  [ 4, 5, 6, 8, 9, 12, 14, 17, 19, 20, 21, 22        ] ],
            [ 'Ep 2',  [ 7, 9, 13, 14, 15, 20, 21                         ] ],
            [ 'Ep 3',  [ 4, 5, 11, 12, 14, 15, 17, 18, 19                 ] ],
            [ 'Ep 4',  [ 2, 4, 5, 6, 7, 11, 12, 13, 26, 27                ] ],
            [ 'Ep 5',  [ 1, 2, 4, 9, 10, 11, 16, 17, 20                   ] ],
            [ 'Ep 6',  [ 1, 2, 3, 4, 10, 18, 19                           ] ],
            [ 'Ga 1',  [ 7, 10, 11, 12                                    ] ],
            [ 'Ga 2',  [ 6, 18, 21                                        ] ],
            [ 'Ga 3',  [ 2, 3, 5, 6, 8, 9, 12, 13, 15, 18, 21, 23, 27, 29 ] ],
            [ 'Ga 4',  [ 6, 7, 8, 22, 23, 24, 25, 26, 28, 31              ] ],
            [ 'Ga 5',  [ 4, 6, 15, 16, 17, 18, 24, 25                     ] ],
            [ 'Ga 6',  [ 3, 5, 6, 8, 12, 13, 15, 16                       ] ],
            [ 'Php 1', [ 9, 10, 11, 23, 24, 25, 28                        ] ],
            [ 'Php 2', [ 1, 2, 4, 5, 6, 7, 9, 11                          ] ],
            [ 'Php 3', [ 7, 9, 11, 13, 21                                 ] ],
            [ 'Php 4', [ 1, 5, 9, 12, 13, 20                              ] ],
            [ 'Cl 1',  [ 3, 4, 5, 6, 9, 11, 14, 17, 18, 23                ] ],
            [ 'Cl 2',  [ 7, 10, 14, 15, 21, 22                            ] ],
            [ 'Cl 3',  [ 2, 3, 13, 14, 16                                 ] ],
            [ 'Cl 4',  [ 3, 4                                             ] ],
        ];

        my $club_100_verses = [
            map {
                my $chapter = $_->[0];
                map { $chapter . ':' . $_ } $_->[1]->@*;
            } @$club_100_matrix
        ];

        my $club_250_verses = [
            @$club_100_verses,
            map {
                my $chapter = $_->[0];
                map { $chapter . ':' . $_ } $_->[1]->@*;
            } @$club_250_matrix
        ];

        my $r = Bible::Reference->new(
            acronyms   => 1,
            sorting    => 1,
            add_detail => 1,
        );

        my $all_verses = $r->clear->in( $self->param('ranges') )->as_verses;

        my $club_100_merge;
        $club_100_merge->{$_}++ for ( @$all_verses, @$club_100_verses );
        my $club_100 = $r->clear->in(
            join( '; ', grep { $club_100_merge->{$_} > 1 } keys %$club_100_merge )
        )->refs;

        my $club_250_merge;
        $club_250_merge->{$_}++ for ( @$all_verses, @$club_250_verses );
        my $club_250 = $r->clear->in(
            join( '; ', grep { $club_250_merge->{$_} > 1 } keys %$club_250_merge )
        )->refs;

        my $full_material = $r->clear->in( $self->param('ranges') )->refs;

        my $label = join( ' ', grep { defined }
            ( ( $self->param('club_100')      ) ? $club_100      . ' (' . $self->param('club_100')      . ')' : undef ),
            ( ( $self->param('club_250')      ) ? $club_250      . ' (' . $self->param('club_250')      . ')' : undef ),
            ( ( $self->param('full_material') ) ? $full_material . ' (' . $self->param('full_material') . ')' : undef ),
            join( ' ', split( /[ \t]*\r?\n[ \t]*/, $self->param('translations') ) ),
        );

        my $material = material_json( label => $label );

        my $quiz = QuizSage::Model::Quiz->new->create({
            user_id   => $self->stash('user')->id,
            importmap => {
                'classes/material'     => 'classes/material.js',
                'classes/queries'      => 'classes/queries.js',
                'classes/quiz'         => 'classes/quiz.js',
                'classes/scoring'      => 'classes/scoring.js',
                'modules/distribution' => 'modules/distribution.js',
            },
            settings => {
                material_id => $material->{material_id},
                teams       => [ map {
                    my ( $team_name, @quizzers ) = split( /[ \t]*\r?\n[ \t]*/ );
                    [ $team_name, [ map { [ split /\s+(?=\S+$)/ ] } @quizzers ] ];
                } split( /\r?\n[ \t]*\r?\n/, $self->param('teams') ) ],
            },
        });

        return $self->redirect_to( '/quiz?id=' . $quiz->id );
    }

    # if ( $self->param('teams') ) {
    #     my $quiz = QuizSage::Model::Quiz->new->load( $self->stash('quiz_id') );

    #     my $submitted_teams = [
    #         grep { length }
    #         map { s/(?:^\s+|\s+$)//g; $_ }
    #         split( /\r?\n/, $self->param('teams') )
    #     ];

    #     my $actual_teams = $quiz->dq
    #         ->sql('SELECT DISTINCT team FROM registration WHERE meet_id = ?')
    #         ->run( $quiz->data->{meet_id} )->column;

    #     my @teams = map {
    #         my $team = $_;
    #         grep { lc $team eq lc $_ } @$actual_teams;
    #     } @$submitted_teams;

    #     if ( @teams == 3 ) {
    #         $quiz->data->{settings} = { $quiz->data->{settings}->%* };
    #         $quiz->data->{settings}{teams} = \@teams;
    #         $quiz->save;

    #         return $self->redirect_to( '/quiz?id=' . $self->stash('quiz_id') );
    #     }
    # }
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

=head2 quiz_password

Handler quiz password. Redirects.

=head2 quiz

Handler for the quiz page.

=head2 quiz_settings

Handler for the quiz settings page.

=head2 quiz_data

Handler for quiz data.

=head2 save_quiz_data

Handler for saving quiz data.

=head1 INHERITANCE

L<Mojolicious::Controller>.
