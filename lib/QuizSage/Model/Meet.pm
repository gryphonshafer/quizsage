package QuizSage::Model::Meet;

use exact -class;
use Mojo::JSON qw( encode_json decode_json );
use QuizSage::Model::Quiz;
use YAML::XS qw( LoadFile Load Dump );

with qw( Omniframe::Role::Bcrypt Omniframe::Role::Model Omniframe::Role::Time QuizSage::Role::Meet::Build );

my $min_passwd_length = 8;

before 'create' => sub ( $self, $params ) {
    $params->{settings} //= LoadFile(
        $self->conf->get( qw( config_app root_dir ) ) . '/config/meets/defaults/meet.yaml'
    );
};

sub freeze ( $self, $data ) {
    $data->{start} = $self->time->parse( $data->{start} )->format('sqlite_min')
        if ( $self->is_dirty( 'start', $data ) );

    if ( $self->is_dirty( 'passwd', $data ) ) {
        croak("Password supplied is not at least $min_passwd_length characters in length")
            unless ( length $data->{passwd} >= $min_passwd_length );
        $data->{passwd} = $self->bcrypt( $data->{passwd} );
    }

    for ( qw( settings build ) ) {
        $data->{$_} = encode_json( $data->{$_} );
        undef $data->{$_} if ( $data->{$_} eq '{}' );
    }

    return $data;
}

sub thaw ( $self, $data ) {
    $data->{$_} = ( defined $data->{$_} ) ? decode_json( $data->{$_} ) : {} for ( qw( settings build ) );
    return $data;
}

sub state ($self) {
    my $state        = $self->data->{build};
    my $quizzes_data = QuizSage::Model::Quiz->new->every_data({ meet_id => $self->id });

    for my $quiz ( $quizzes_data->@* ) {
        my ($state_bracket) = grep { $_->{name} eq $quiz->{bracket} } $state->{brackets}->@*;
        my ($state_quiz)    =
            grep { $_->{name} eq $quiz->{name} }
            map { $_->{rooms}->@* }
            $state_bracket->{sets}->@*;

        $state_quiz->{id} = $quiz->{quiz_id};

        for ( my $i = 0; $i < $state_quiz->{roster}->@*; $i++ ) {
            $state_quiz->{roster}[$i]{$_} //= $quiz->{settings}{teams}[$i]{$_}
                for ( keys $quiz->{settings}{teams}[$i]->%* );
        }
    }

    my $quizzes_done = [ grep { not grep { $_->{current} } $_->{state}{board}->@* } @$quizzes_data ];
    my $brackets_done;

    my $find_team_done = sub ( $bracket, $team ) {
        my $team_done = undef;

        if ( $team->{position} and $team->{quiz} ) {
            my ($quiz_done) = grep {
                $_->{bracket} eq $bracket->{name} and
                $_->{name} eq $team->{quiz}
            } @$quizzes_done;

            ($team_done) =
                map {
                    my $team_name = $_->{name};
                    my ($team) = grep { $_->{name} eq $team_name } $state->{roster}->@*;
                    $team;
                }
                grep { $_->{score}{position} == $team->{position} }
                $quiz_done->{state}{teams}->@*
                if $quiz_done;
        }
        elsif ( $team->{position} and $team->{bracket} ) {
            my $bracket_done = $brackets_done->{ $team->{bracket} };

            ($team_done) =
                grep {
                    $bracket_done->[ $team->{position} - 1 ] and
                    $_->{name} eq $bracket_done->[ $team->{position} - 1 ]
                }
                $state->{roster}->@*
                if $bracket_done;
        }

        return $team_done;
    };

    for my $bracket ( $state->{brackets}->@* ) {
        my @state_quizzes = map { $_->{rooms}->@* } $bracket->{sets}->@*;

        if ( $bracket->{rankings} ) {
            $brackets_done->{ $bracket->{name} } = [ (undef) x $bracket->{rankings}->@* ];

            for ( my $i = 0; $i < $bracket->{rankings}->@*; $i++ ) {
                my $team_done = $find_team_done->( $bracket, $bracket->{rankings}[$i] );
                $brackets_done->{ $bracket->{name} }[$i] = $team_done->{name} if $team_done;
            }

            next;
        }

        # next unless all the quizzes in this bracket done
        next unless (
            @state_quizzes ==
            grep {
                my $name = $_->{name};
                grep { $_->{bracket} eq $bracket->{name} and $_->{name} eq $name } @$quizzes_done;
            } @state_quizzes
        );

        # determine score sum ranking
        my $teams_points;
        $teams_points->{ $_->{name} } += $_->{score}{points} for (
            map { $_->{state}{teams}->@* }
            grep { $_->{bracket} eq $bracket->{name} } @$quizzes_done
        );
        $brackets_done->{ $bracket->{name} } = [
            map { $_->[0] }
            sort { $b->[1] <=> $a->[1] }
            map { [ $_, $teams_points->{$_} // 0 ] }
            keys %$teams_points
        ];
    }

    for my $bracket ( $state->{brackets}->@* ) {
        for my $quiz ( map { $_->{rooms}->@* } $bracket->{sets}->@* ) {
            for my $team ( $quiz->{roster}->@* ) {
                next if ( $team->{name} );
                my $team_done = $find_team_done->( $bracket, $team );
                $team->{$_} //= $team_done->{$_} for ( keys %$team_done );
            }
        }
    }

    return $state;
}

sub quiz_settings ( $self, $bracket_name, $quiz_name ) {
    my $build = Load( Dump( $self->data->{build} ) );

    my ($bracket) = grep { $_->{name} eq $bracket_name } $build->{brackets}->@*;
    return unless $bracket;

    my $find_pointers = sub {
        for my $set ( $bracket->{sets}->@* ) {
            for my $quiz ( $set->{rooms}->@* ) {
                return $quiz, $set, $bracket if ( $quiz->{name} eq $quiz_name );
            }
        }
    };
    my ( $quiz, $set );
    ( $quiz, $set, $bracket ) = $find_pointers->();

    return unless $quiz;

    $quiz->{$_} //= $set->{$_} // $bracket->{$_} // $build->{per_quiz}{$_}
        for ( qw( application importmap material inputs ) );

    delete $quiz->{name};
    $quiz->{teams} = delete $quiz->{roster};

    return $quiz;
}

1;

=head1 NAME

QuizSage::Model::Meet

=head1 SYNOPSIS

    use QuizSage::Model::Meet;

    my $quiz = QuizSage::Model::Meet->new;

=head1 DESCRIPTION

This class is the model for meet objects.

=head1 OBJECT METHODS

=head2 freeze, thaw

=head2 state

=head2 quiz_settings

=head1 WITH ROLES

L<Omniframe::Role::Bcrypt>, L<Omniframe::Role::Model>, L<Omniframe::Role::Time>,
L<QuizSage::Role::Meet::Build>.
