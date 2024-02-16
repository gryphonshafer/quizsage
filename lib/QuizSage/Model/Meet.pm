package QuizSage::Model::Meet;

use exact -class;
use Mojo::JSON qw( encode_json decode_json );
use QuizSage::Model::Quiz;

with qw(
    Omniframe::Role::Bcrypt
    Omniframe::Role::Model
    Omniframe::Role::Time
    QuizSage::Role::Meet::Build
    QuizSage::Role::Data
);

my $min_passwd_length = 8;

before 'create' => sub ( $self, $params ) {
    $params->{settings} //= $self->dataload('config/meets/defaults/meet.yaml');
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
        undef $data->{$_} if ( $data->{$_} eq '{}' or $data->{$_} eq 'null' );
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

        if ( $quiz->{state} and $quiz->{state}{board} ) {
            my ($current) = grep { $_->{current} } $quiz->{state}{board}->@*;
            $state_quiz->{current_query_id} = $current->{id} if ($current);
            $state_quiz->{roster} = $quiz->{state}{teams} if ( $quiz->{state}{teams} );
        }
        else {
            $state_quiz->{current_query_id} = '1A';
        }

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
    my $build = $self->deepcopy( $self->data->{build} );

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

    for ( qw( js_apps_id module defer importmap inputs material ) ) {
        $quiz->{$_} //= $set->{$_} // $bracket->{$_} // ( $build->{per_quiz} // {} )->{$_};
        delete $quiz->{$_} unless ( defined $quiz->{$_} );
    }

    delete $quiz->{name};
    $quiz->{teams} = delete $quiz->{roster};

    return $quiz;
}

sub stats ($self) {
    my $build        = $self->data->{build};
    my $quizzes_data = QuizSage::Model::Quiz->new->every_data({ meet_id => $self->id });

    my $stats;

    for my $bracket ( $build->{brackets}->@* ) {
        push( @{ $stats->{rankings} }, {
            bracket   => $bracket->{name},
            positions => [ map {
                my $rank = $_;

                my ($quiz) = grep {
                    $bracket->{name} eq $_->{bracket} and
                    $rank->{quiz} eq $_->{name}
                } @$quizzes_data;

                if ($quiz) {
                    my ($team) = grep { $rank->{position} == $_->{score}{position} } $quiz->{state}{teams}->@*;
                    $rank->{team} = $team->{name} if ($team);
                }

                $rank;
            } $bracket->{rankings}->@* ],
        } ) if ( $bracket->{rankings} );

        for my $quiz ( map { $_->{rooms}->@* } $bracket->{sets}->@* ) {
            my ($quiz_data) = grep {
                $_->{bracket} eq $bracket->{name} and
                $_->{name} eq $quiz->{name}
            } @$quizzes_data;

            if ( $quiz_data and $quiz_data->{state} ) {
                for my $team ( $quiz_data->{state}{teams}->@* ) {
                    push( @{ $stats->{teams}{ $team->{name} } }, {
                        bracket  => $bracket->{name},
                        name     => $quiz->{name},
                        weight   => $quiz->{weight} // $bracket->{weight} // 1,
                        points   => $team->{score}{points},
                        position => $team->{score}{position},
                    } );

                    for my $quizzer ( $team->{quizzers}->@* ) {
                        push( @{ $stats->{quizzers}{ $quizzer->{name} } }, {
                            bracket => $bracket->{name},
                            name    => $quiz->{name},
                            weight  => $quiz->{weight} // $bracket->{weight} // 1,
                            points  => $quizzer->{score}{points},
                            vra     => scalar( grep {
                                $_->{action}     eq 'correct'            and
                                $_->{quizzer_id} eq $quizzer->{id}       and
                                $_->{team_id}    eq $team->{id}          and
                                index( uc( $_->{qsstypes} ), 'V' ) != -1 and
                                index( uc( $_->{qsstypes} ), 'R' ) != -1 and
                                index( uc( $_->{qsstypes} ), 'A' ) != -1
                            } $quiz_data->{state}{events}->@* ),
                        } );
                    }
                }
            }
        }
    }

    for my $type ( qw( teams quizzers ) ) {
        my ( $position, $quizzes_max ) = ( 0, 0 );

        $stats->{$type} = [
            sort {
                $b->{points_avg} <=> $a->{points_avg} or
                $b->{points_sum} <=> $a->{points_sum} or
                $a->{name} cmp $b->{name}
            }
            map {
                my ( $quizzes, $points_sum, $points_avg ) = ( $stats->{$type}{$_}, 0, 0 );
                $quizzes_max = @$quizzes if ( @$quizzes > $quizzes_max );

                $points_sum += $_->{points} * $_->{weight} for (@$quizzes);
                $points_avg = $points_sum / scalar grep { $_->{weight} } @$quizzes;

                my $stat = {
                    name       => $_,
                    quizzes    => $quizzes,
                    points_sum => $points_sum,
                    points_avg => $points_avg,
                };

                if ( $type eq 'quizzers' ) {
                    my $name = $_;

                    my ($team) = grep {
                        my ($quizzer) = grep { $_->{name} eq $name } $_->{quizzers}->@*;
                        $stat->{tags} //= $quizzer->{tags} if ($quizzer);
                    } $build->{roster}->@*;

                    $stat->{team_name} = $team->{name};
                }

                $stat;
            } keys $stats->{$type}->%*,
        ];

        $stats->{meta}{$type} = {
            quizzes_max => $quizzes_max,
        };
    };

    $stats->{vra_quizzers} = [
        sort { $b->{vra_sum} <=> $a->{vra_sum} or $b->{points_sum} <=> $a->{points_sum} }
        grep { $_->{vra_sum} }
        map {
            my $quizzer = $_;
            $quizzer->{vra_sum} = 0;
            $quizzer->{vra_sum} += $_->{vra} for ( $quizzer->{quizzes}->@* );
            $quizzer;
        } $stats->{quizzers}->@*
    ];

    return $stats;
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

=head2 stats

=head1 WITH ROLES

L<Omniframe::Role::Bcrypt>, L<Omniframe::Role::Model>, L<Omniframe::Role::Time>,
L<QuizSage::Role::Meet::Build>, L<QuizSage::Role::Data>.
