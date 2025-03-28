package QuizSage::Model::Meet;

use exact -class, -conf;
use Mojo::JSON qw( to_json from_json );
use Omniframe::Class::Time;
use Omniframe::Util::Bcrypt 'bcrypt';
use Omniframe::Util::Data qw( dataload deepcopy );
use QuizSage::Model::Quiz;
use QuizSage::Model::Season;

with qw(
    Omniframe::Role::Model
    QuizSage::Role::Meet::Build
    QuizSage::Role::Meet::Settings
    QuizSage::Role::Meet::Editing
);

my $time = Omniframe::Class::Time->new;

before 'create' => sub ( $self, $params ) {
    $params->{settings} //= dataload('config/meets/defaults/meet.yaml');
};

sub freeze ( $self, $data ) {
    $data->{start} = $time->parse( $data->{start} )->format('sqlite_min')
        if ( $self->is_dirty( 'start', $data ) );

    my $min_passwd_length = conf->get('min_passwd_length');
    if ( $self->is_dirty( 'passwd', $data ) ) {
        croak("Password supplied is not at least $min_passwd_length characters in length")
            unless ( length $data->{passwd} >= $min_passwd_length );
        $data->{passwd} = bcrypt( $data->{passwd} );
    }

    for ( qw( settings build stats ) ) {
        $data->{$_} = to_json( $data->{$_} );
        undef $data->{$_} if ( $data->{$_} eq '{}' or $data->{$_} eq 'null' );
    }

    return $data;
}

sub thaw ( $self, $data ) {
    $data->{$_} = ( defined $data->{$_} ) ? from_json( $data->{$_} ) : {}
        for ( qw( settings build stats ) );
    return $data;
}

sub from_season_meet ( $self, $season_name, $meet_name ) {
    my $season = QuizSage::Model::Season->new->load({ name => $season_name })
        or croak qq{Unable to locate season based on name: "$season_name"};

    my $meet = $self->new->load({ name => $meet_name, season_id => $season->id })
        or croak qq{Unable to locate meet based on name: "$meet_name"};

    return $meet;
}

sub state ($self) {
    my $state        = deepcopy( $self->data->{build} );
    my $quizzes_data = QuizSage::Model::Quiz->new->every_data({ meet_id => $self->id });

    # for every bracket that has a first-to-win-twice finals situation
    for my $bracket (
        grep {
            $_->{finals} and $_->{finals} eq 'first_to_win_twice'
        } $state->{brackets}->@*
    ) {
        my @bracket_quizzes = grep { $_->{bracket} eq $bracket->{name} } @$quizzes_data;

        my $first_finals_quiz            = $bracket->{sets}[-1]{rooms}[0];
        my $first_finals_quiz_name       = quotemeta( $first_finals_quiz->{name} );
        my $first_finals_quiz_name_regex = qr/^$first_finals_quiz_name(?:\-\d+)?$/;
        my ($first_finals_quiz_template) =
            map { $_->{sets}[-1]{rooms}[0] }
            grep { $_->{name} eq $bracket->{name} }
            $self->data->{build}{brackets}->@*;

        # inject missing finals quizzes into meet state data
        for my $quiz (@bracket_quizzes) {
            next if (
                $quiz->{name} !~ $first_finals_quiz_name_regex or
                grep { $_->{name} eq $quiz->{name} } $bracket->{sets}[-1]{rooms}->@*
            );
            my $next_finals_quiz = deepcopy($first_finals_quiz_template);
            $next_finals_quiz->{name} = $quiz->{name};
            push( $bracket->{sets}[-1]{rooms}->@*, $next_finals_quiz );
        }

        # skip bracket if not every quiz in the bracket is complete
        next if (
            grep {
                not $_->{state} or
                not $_->{state}{board} or
                not $_->{state}{board}->@*
            } @bracket_quizzes or
            grep { grep { $_->{current} } $_->{state}{board}->@* } @bracket_quizzes or
            @bracket_quizzes != map { $_->{rooms}->@* } $bracket->{sets}->@*,
        );

        my @finals_quizzes_done = grep {
            $_->{bracket} eq $bracket->{name} and
            $_->{name} =~ $first_finals_quiz_name_regex and
            (
                $_->{state}{board}->@* and
                not grep { $_->{current} } $_->{state}{board}->@*
            )
        } @bracket_quizzes;

        # has the first-to-win-twice condition not yet been met
        my $winners;
        for my $quiz (@finals_quizzes_done) {
            my ($winner) = grep { $_->{score}{position} == 1 } $quiz->{state}{teams}->@*;
            $winners->{ $winner->{name} }++;
        }
        unless ( grep { $winners->{$_} >= 2 } keys %$winners ) {

            # inject an additional finals quiz into meet state
            my $next_finals_quiz = deepcopy($first_finals_quiz_template);
            $next_finals_quiz->{name} .= '-' . ( @finals_quizzes_done + 1 );
            push( $bracket->{sets}[-1]{rooms}->@*, $next_finals_quiz );
        }
    }

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

        if ( $state_quiz->{roster} ) {
            for ( my $i = 0; $i < $state_quiz->{roster}->@*; $i++ ) {
                $state_quiz->{roster}[$i]{$_} //= $quiz->{settings}{teams}[$i]{$_}
                    for ( keys $quiz->{settings}{teams}[$i]->%* );
            }
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

        # determine team sort ranking via the following tie breaking sequence:
        #     1. points average for the bracket
        #     2. points sum for the bracket
        #     3. highest cumulative positions (i.e. 1st + 3nd > 3rd + 2nd )
        #     4. total bonus team points
        #     5. more total # of quizzes > fewer total # of quizzes
        #     6. fewer total # of quizzers > more total # of quizzers
        #     7. reverse of team name (i.e. MAD 1 > GIG 1 and MAD 1 > ELK 2 and ELK 2 > KIT 2)
        my $bracket_team_sorting_data;
        for my $team (
            map { $_->{state}{teams}->@* }
            grep { $_->{state}{teams} }
            grep { $_->{bracket} eq $bracket->{name} }
            @$quizzes_done
        ) {
            $bracket_team_sorting_data->{ $team->{name} }->{points_sum}      += $team->{score}{points};
            $bracket_team_sorting_data->{ $team->{name} }->{positions_sum}   += $team->{score}{position};
            $bracket_team_sorting_data->{ $team->{name} }->{team_points_sum} += $team->{score}{bonuses};

            $bracket_team_sorting_data->{ $team->{name} }->{total_quizzes}++;
            $bracket_team_sorting_data->{ $team->{name} }->{total_quizzers} //= $team->{quizzers}->@*;
            $bracket_team_sorting_data->{ $team->{name} }->{reverse_name}   //= reverse $team->{name};
        }
        $brackets_done->{ $bracket->{name} } = [
            map { $_->[0] }
            sort {
                $b->[1]{points_avg} <=> $a->[1]{points_avg} or
                $b->[1]{points_sum} <=> $a->[1]{points_sum} or
                $b->[1]{positions_sum} <=> $a->[1]{positions_sum} or
                $b->[1]{team_points_sum} <=> $a->[1]{team_points_sum} or
                $b->[1]{total_quizzes} <=> $a->[1]{total_quizzes} or
                $a->[1]{total_quizzers} <=> $b->[1]{total_quizzers} or
                $a->[1]{reverse_name} cmp $b->[1]{reverse_name}
            }
            map {
                my $data = $bracket_team_sorting_data->{$_};
                $data->{points_avg} = $data->{points_sum} / $data->{total_quizzes};
                [ $_, $data ];
            }
            keys %$bracket_team_sorting_data
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
    my $build = deepcopy( $self->data->{build} );

    my ($bracket) = grep { $_->{name} eq $bracket_name } $build->{brackets}->@*;
    return unless $bracket;

    my $find_pointers = sub {
        for my $set ( $bracket->{sets}->@* ) {
            for my $quiz ( $set->{rooms}->@* ) {
                return $quiz, $set, $bracket if (
                    $quiz->{name} eq $quiz_name
                );
            }
        }

        for my $set ( $bracket->{sets}->@* ) {
            for my $quiz ( $set->{rooms}->@* ) {
                my $quotemeta = quotemeta( $quiz->{name} );
                my $regex     = qr/^$quotemeta(?:\-\d+)?$/;

                if ( $quiz_name =~ $regex ) {
                    delete $quiz->{distribution};
                    return $quiz, $set, $bracket;
                }
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

sub distribution ($self) {
    my $build = $self->data->{build};

    for my $bracket ( $build->{brackets}->@* ) {
        for my $quiz ( map { $_->{rooms}->@* } $bracket->{sets}->@* ) {
            if ( grep { $_->{bible} and $_->{bible} eq '?' } $quiz->{distribution}->@* ) {
                try {
                    my $quiz_obj = QuizSage::Model::Quiz->new->load({
                        meet_id => $self->id,
                        bracket => $bracket->{name},
                        name    => $quiz->{name},
                    });

                    $quiz->{distribution} = $quiz_obj->data->{settings}{distribution}
                        if ( $quiz_obj->data->{settings}{distribution} );
                }
                catch ($e) {}
            }
        }
    }

    return $build;
}

sub stats ( $self, $rebuild = 0 ) {
    return $self->data->{stats} if (
        not $rebuild and
        $self->data->{stats}->%* and
        $time->parse( $self->data->{last_modified} )->{datetime}->epoch >
        $time->parse( conf->get('rebuild_stats_if_before') )->{datetime}->epoch
    );

    my $build        = deepcopy( $self->data->{build} );
    my $quizzes_data = QuizSage::Model::Quiz->new->every_data({ meet_id => $self->id });

    my $stats;

    my $first_to_win_twice_positions_cache;
    my $first_to_win_twice_positions = sub (
        $position,
        $finals_quizzes,
        $meet_quizzes,
        $bracket_name,
    ) {
        unless ($first_to_win_twice_positions_cache) {

            # has the first-to-win-twice condition been met
            my $winners;
            for my $quiz (@$finals_quizzes) {
                my ($winner) = grep { $_->{score}{position} == 1 } $quiz->{state}{teams}->@*;
                $winners->{ $winner->{name} }++;
            }
            if ( grep { $winners->{$_} >= 2 } keys %$winners ) {
                my @positions;

                # first team to win first place twice is the winner
                my ($winner) =
                    map { $_->[0] }
                    sort { $b->[1] <=> $a->[1] }
                    map { [ $_, $winners->{$_} ] }
                    keys %$winners;
                push( @positions, $winner );

                # remaining placements are based on total positional placement by team,
                # unless there is a tie
                my $team_position_total;
                $team_position_total->{ $_->{name} } += $_->{score}{position}
                    for ( grep { $_->{name} ne $winner } map { $_->{state}{teams}->@* } @$finals_quizzes );
                my $teams_by_position_total;
                push( $teams_by_position_total->{ $team_position_total->{$_} }->@*, $_ )
                    for ( keys %$team_position_total );

                for my $total ( sort { $a <=> $b } keys %$teams_by_position_total ) {
                    if ( $teams_by_position_total->{$total}->@* == 1 ) {
                        push( @positions, $teams_by_position_total->{$total}[0] );
                    }
                    else {
                        # if there is a tie, the meet director will break it in the following way:
                        #     1. score sum for finals bracket quizzes
                        #     2. score sum for the positional bracket
                        #     3. score sum for the entire meet
                        push( @positions,
                            map { $_->{team } }
                            sort {
                                $b->{score_sum_final_backet}       <=> $a->{score_sum_final_backet}       or
                                $b->{score_sum_positional_bracket} <=> $a->{score_sum_positional_bracket} or
                                $b->{score_sum_entire_meet}        <=> $a->{score_sum_entire_meet}        or
                                $b->{team}                         <=> $a->{team}
                            }
                            map {
                                my $team = $_;

                                my $score_sum_final_backet = 0;
                                $score_sum_final_backet += $_->{score}{points} for (
                                    grep { $_->{name} eq $team }
                                    map { $_->{state}{teams}->@* }
                                    @$finals_quizzes
                                );

                                my $score_sum_positional_bracket = 0;
                                $score_sum_positional_bracket += $_->{score}{points} for (
                                    grep { $_->{name} eq $team }
                                    map { $_->{state}{teams}->@* }
                                    grep { $_->{bracket} eq $bracket_name }
                                    @$meet_quizzes
                                );

                                my $score_sum_entire_meet = 0;
                                $score_sum_entire_meet += $_->{score}{points} for (
                                    grep { $_->{name} eq $team }
                                    map { $_->{state}{teams}->@* }
                                    @$meet_quizzes
                                );

                                +{
                                    team                         => $team,
                                    score_sum_final_backet       => $score_sum_final_backet,
                                    score_sum_positional_bracket => $score_sum_positional_bracket,
                                    score_sum_entire_meet        => $score_sum_entire_meet,
                                };
                            } $teams_by_position_total->{$total}->@*
                        );
                    }
                }

                $first_to_win_twice_positions_cache = \@positions;
            }
        }

        return ($first_to_win_twice_positions_cache)
            ? $first_to_win_twice_positions_cache->[ $position - 1 ]
            : undef;
    };

    my $gross_points_by_quizzer_by_bibles;

    for my $bracket ( $build->{brackets}->@* ) {
        push( @{ $stats->{rankings} }, {
            bracket   => $bracket->{name},
            positions => [ map {
                my $rank = $_;

                my @quizzes = grep {
                    my $quotemeta = quotemeta( $rank->{quiz} );
                    my $regex     = qr/^$quotemeta(?:\-\d+)?$/;

                    $bracket->{name} eq $_->{bracket} and
                    (
                        $_->{name} eq $rank->{quiz} or
                        $_->{name} =~ $regex
                    );
                } @$quizzes_data;

                if ( $bracket->{finals} and $bracket->{finals} eq 'first_to_win_twice' and @quizzes > 1 ) {
                    $rank->{team} = $first_to_win_twice_positions->(
                        $rank->{position},
                        \@quizzes,
                        $quizzes_data,
                        $bracket->{name},
                    );
                    $rank->{quiz} .= '*';
                }
                elsif ( my $quiz = $quizzes[0] ) {
                    $rank->{quiz_id} = $quiz->{quiz_id};
                    my ($team) =
                        grep { $rank->{position} == $_->{score}{position} }
                        $quiz->{state}{teams}->@*;
                    $rank->{team} = $team->{name} if ($team);
                }

                $rank;
            } $bracket->{rankings}->@* ],
        } ) if ( $bracket->{rankings} );

        for my $quiz ( map { $_->{rooms}->@* } $bracket->{sets}->@* ) {
            my $quotemeta = quotemeta( $quiz->{name} );
            my $regex     = qr/^$quotemeta(?:\-\d+)?$/;
            my @quiz_data = grep {
                $_->{bracket} eq $bracket->{name} and
                (
                    $_->{name} eq $quiz->{name} or
                    $_->{name} =~ $regex
                ) and
                $_->{state}
            } @$quizzes_data;

            for my $quiz_data (@quiz_data) {
                my $bibles = {
                    map { $_->{bible} => 1 }
                    grep { $_->{bible} }
                    $quiz_data->{settings}{distribution}->@*
                };
                $bibles = ( keys %$bibles > 1 ) ? 'multiple' : 'singular';

                for my $team ( $quiz_data->{state}{teams}->@* ) {
                    push( @{ $stats->{teams}{ $team->{name} } }, {
                        quiz_id  => $quiz_data->{quiz_id},
                        bracket  => $bracket->{name},
                        name     => $quiz_data->{name},
                        weight   => $quiz->{weight} // $bracket->{weight} // 1,
                        points   => $team->{score}{points},
                        position => $team->{score}{position},
                        bibles   => $bibles,
                    } );

                    for my $quizzer ( $team->{quizzers}->@* ) {
                        push(
                            @{ $gross_points_by_quizzer_by_bibles->{ $quizzer->{name} }{$bibles} },
                            $quizzer->{score}{points},
                        );
                        push( @{ $stats->{quizzers}{ $quizzer->{name} } }, {
                            quiz_id => $quiz_data->{quiz_id},
                            bracket => $bracket->{name},
                            name    => $quiz_data->{name},
                            weight  => $quiz->{weight} // $bracket->{weight} // 1,
                            points  => $quizzer->{score}{points},
                            bibles  => $bibles,
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

    my @boosts;
    for my $quizzer (
        grep {
            $_->{singular} and
            $_->{multiple}
        }
        values %$gross_points_by_quizzer_by_bibles
    ) {
        my %points_avg = map {
            my $points;
            $points += $_ for ( $quizzer->{$_}->@* );
            $_ => $points / @{ $quizzer->{$_} };
        } keys %$quizzer;
        push( @boosts, $points_avg{multiple} / $points_avg{singular} )
            if ( $points_avg{multiple} and $points_avg{singular} );
    }
    my $factor;
    if (@boosts) {
        $factor += $_ for (@boosts);
        $factor /= @boosts;
    }
    $stats->{meta}{foreign_bibles_boost_factor} = ( defined $factor and $factor > 1 ) ? $factor : 1;

    my %unique_tags;
    for my $type ( qw( teams quizzers ) ) {
        my ( $position, $quizzes_max ) = ( 0, 0 );

        $stats->{$type} = [
            sort {
                $b->{points_avg} <=> $a->{points_avg} or
                $b->{points_sum} <=> $a->{points_sum} or
                $a->{name} cmp $b->{name}
            }
            map {
                my $quizzes = $stats->{$type}{$_};
                my ( $points_sum, $points_avg, $points_sum_raw, $points_avg_raw ) = (0) x 4;
                $quizzes_max = @$quizzes if ( @$quizzes > $quizzes_max );

                for (@$quizzes) {
                    $points_sum_raw += $_->{points} * $_->{weight};
                    $points_sum     += $_->{points} * $_->{weight} * (
                        ( $_->{bibles} eq 'multiple' )
                            ? $stats->{meta}{foreign_bibles_boost_factor}
                            : 1
                    );
                }
                $points_avg     = $points_sum     / scalar grep { $_->{weight} } @$quizzes;
                $points_avg_raw = $points_sum_raw / scalar grep { $_->{weight} } @$quizzes;

                if ( $rebuild and $rebuild eq 'raw' ) {
                    $stats->{meta}{foreign_bibles_boost_factor} = 1;
                    $points_sum = $points_sum_raw;
                    $points_avg = $points_avg_raw;
                }

                my $stat = {
                    name           => $_,
                    quizzes        => $quizzes,
                    points_sum     => $points_sum,
                    points_avg     => $points_avg,
                    points_sum_raw => $points_sum_raw,
                    points_avg_raw => $points_avg_raw,
                };

                if ( $type eq 'quizzers' ) {
                    my $name = $_;

                    my ($team) = grep {
                        my ($quizzer) = grep { $_->{name} eq $name } $_->{quizzers}->@*;
                        $stat->{tags} //= $quizzer->{tags} if ($quizzer);
                    } $build->{roster}->@*;

                    $unique_tags{$_}++ for ( $stat->{tags}->@* );
                    $stat->{team_name} = $team->{name};
                }

                $stat;
            } keys $stats->{$type}->%*,
        ];

        $stats->{meta}{$type} = {
            quizzes_max => $quizzes_max,
        };
    };
    $stats->{tags} = [ sort keys %unique_tags ];

    $stats->{vra_quizzers} = [
        sort {
            $b->{vra_sum} <=> $a->{vra_sum} or
            $b->{points_sum} <=> $a->{points_sum} or
            $a->{name} cmp $b->{name}
        }
        grep { $_->{vra_sum} }
        map {
            my $quizzer = $_;
            $quizzer->{vra_sum} = 0;
            $quizzer->{vra_sum} += $_->{vra} for ( $quizzer->{quizzes}->@* );
            $quizzer;
        } $stats->{quizzers}->@*
    ];

    my $orgs;
    for my $team ( $stats->{teams}->@* ) {
        my ( $org, $name_suffix ) = split( /\s(?=\S+$)/, $team->{name} );
        push( $orgs->{$org}{teams}->@*, $team );
    }
    $stats->{orgs} = [
        sort {
            $b->{points_avg} <=> $a->{points_avg} or
            $a->{name} cmp $b->{name}
        }
        map {
            my $org_name = $_;
            my $org_data = {
                name       => $org_name,
                points_sum => 0,
                quizzes    => 0,
                teams      => scalar( $orgs->{$org_name}{teams}->@* ),
            };

            for my $team ( $orgs->{$org_name}{teams}->@* ) {
                $org_data->{points_sum} += $team->{points_sum};
                $org_data->{quizzes}    += scalar( $team->{quizzes}->@* );
            }

            $org_data->{points_avg} = ( $org_data->{quizzes} )
                ? $org_data->{points_sum} / $org_data->{quizzes}
                : 0;

            $org_data;
        }
        keys %$orgs
    ];

    my $rookies_of_the_meets_from_previous_meets = [];
    for my $previous_meet (
        $self->new->every_data(
            {
                season_id => $self->data->{season_id},
                start     => { '<' => $self->data->{start} },
            },
            {
                order_by => 'start',
            },
        )->@*
    ) {
        for my $rookie (
            grep {
                grep { $_ eq 'Rookie' } $_->{tags}->@*
            } $previous_meet->{stats}{quizzers}->@*
        ) {
            if ( not grep { $_ eq $rookie->{name} } @$rookies_of_the_meets_from_previous_meets ) {
                push( @$rookies_of_the_meets_from_previous_meets, $rookie->{name} );
                last;
            }
        }
    }
    for my $rookie (
        grep {
            grep { $_ eq 'Rookie' } $_->{tags}->@*
        } $stats->{quizzers}->@*
    ) {
        if ( not grep { $_ eq $rookie->{name} } @$rookies_of_the_meets_from_previous_meets ) {
            $stats->{meta}{rookie_of_the_meet} = {
                map { $_ => $rookie->{$_} } qw(
                    name
                    points_avg
                    points_avg_raw
                    points_sum
                    points_sum_raw
                    team_name
                    vra_sum
                )
            };

            last;
        }
    }

    $self->data->{stats}         = $stats;
    $self->data->{last_modified} = \q{ STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' ) },
    $self->save;
    $self->info( 'Meet stats generated for: ' . $self->id );

    return $stats;
}

sub admin_auth ( $self, $user ) {
    return (
        $self->dq->sql(q{
            SELECT COUNT(*)
            FROM season
            WHERE season_id = ? AND user_id = ?
        })->run( $self->data->{season_id}, $user->id )->value
        or
        $self->dq->sql(q{
            SELECT COUNT(*)
            FROM administrator
            WHERE meet_id = ? AND user_id = ?
        })->run( $self->id, $user->id )->value
    ) ? 1 : 0;
}

sub admin ( $self, $action, $user_id ) {
    $self->dq->sql(
        ( $action eq 'add' )
            ? 'INSERT INTO administrator ( user_id, meet_id ) VALUES ( ?, ? )'
            : 'DELETE FROM administrator WHERE user_id = ? AND meet_id = ?'
    )->run( $user_id, $self->id );

    return $self;
}

sub admins ($self) {
    return $self->dq->sql(q{
        SELECT u.first_name, u.last_name, u.email, u.user_id
        FROM user AS u
        JOIN administrator AS a USING (user_id)
        WHERE a.meet_id = ?
        ORDER BY 1, 2, 3
    })->run( $self->id )->all({});
}

sub swap_draw_parts ( $self, $bracket_name, $sets = [], $quizzes = [] ) {
    croak('Meet not loaded') unless ( $self->id );
    croak('Meet has not yet been built') unless ( $self->data->{build} );

    my ($bracket) = grep { $_->{name} eq $bracket_name } $self->data->{build}{brackets}->@*;
    croak('Bracket specified not found') unless ($bracket);

    my $count = $self->dq->sql('SELECT COUNT(*) FROM quiz WHERE meet_id = ? AND bracket = ? AND name = ?');
    for my $name ( map { $_->{name} } map { $bracket->{sets}[ $_ - 1 ]{rooms}->@* } $sets->@* ) {
        croak('Quiz $name already exists and therefore prevents swapping its set')
            if ( $count->run( $self->id, $bracket_name, $name )->value );
    }

    while ( $sets->@* ) {
        my @sets = ( shift $sets->@*, shift $sets->@* );
        my ( $quizzes_a, $quizzes_b ) = map { $bracket->{sets}[ $_ - 1 ]->{rooms} } @sets;

        if ( $quizzes_a->@* == $quizzes_b->@* ) {
            for my $property ( qw{ roster distribution } ) {
                my @properties_a = map { $_->{$property} } $quizzes_a->@*;
                my @properties_b = map { $_->{$property} } $quizzes_b->@*;

                $_->{$property} = shift @properties_b for ( $quizzes_a->@* );
                $_->{$property} = shift @properties_a for ( $quizzes_b->@* );
            }
        }
        else {
            my @names = map { $_->{name} } map { $_->{rooms}->@* } $bracket->{sets}->@*;

            my %set_a = $bracket->{sets}[ $sets[0] - 1 ]->%*;
            my %set_b = $bracket->{sets}[ $sets[1] - 1 ]->%*;

            my $schedule_a = $set_a{rooms}[0]{schedule};
            my $schedule_b = $set_b{rooms}[0]{schedule};

            $_->{schedule} = $schedule_b for ( $set_a{rooms}->@* );
            $_->{schedule} = $schedule_a for ( $set_b{rooms}->@* );

            %{ $bracket->{sets}[ $sets[0] - 1 ] } = %set_b;
            %{ $bracket->{sets}[ $sets[1] - 1 ] } = %set_a;

            $_->{name} = shift @names for ( map { $_->{rooms}->@* } $bracket->{sets}->@* );
        }
    }

    while ( $quizzes->@* ) {
        my @quizzes = ( shift $quizzes->@*, shift $quizzes->@* );

        my ($quiz_a) = grep { $_->{name} eq $quizzes[0] } map { $_->{rooms}->@* } $bracket->{sets}->@*;
        my ($quiz_b) = grep { $_->{name} eq $quizzes[1] } map { $_->{rooms}->@* } $bracket->{sets}->@*;

        for my $property ( qw{ roster distribution } ) {
            my $property_a = $quiz_a->{$property};
            my $property_b = $quiz_b->{$property};

            $quiz_a->{$property} = $property_b;
            $quiz_b->{$property} = $property_a;
        }
    }

    $self->save;
    return;
}

1;

=head1 NAME

QuizSage::Model::Meet

=head1 SYNOPSIS

    use QuizSage::Model::Meet;

    my $meet          = QuizSage::Model::Meet->new->load(1138);
    my $state         = $meet->state;
    my $quiz_settings = $meet->quiz_settings( 'Bracket Name', 'Quiz Name' );
    my $stats         = $meet->stats;

    $meet->swap_draw_parts( 'Preliminary', [ 1, 4 ], [ 3, 12 ] );

=head1 DESCRIPTION

This class is the model for meet objects.

=head1 EXTENDED METHOD

=head2 create

Extended from L<Omniframe::Role::Model>, this method will populate the
C<settings> value from C<config/meets/defaults/meet.yaml> if that value isn't
explicitly provided.

=head1 OBJECT METHODS

=head2 freeze, thaw

Likely not used directly, these methods will cause L<Omniframe::Role::Model> to
canonically format the C<start> datetime and JSON-encode/decode the C<settings>
hashref and the C<build> hashref.

Also, it will C<bcrypt> passwords before storing them in the database. It
expects a hashref of values and will return a hashref of values with the
C<passwd> crypted.

=head2 from_season_meet

This method requires a season name and meet name. It will attempt to find and
return a loaded meet object for the meet matching the input names.

    my $meet = QuizSage::Model::Meet->new
        ->from_season_meet( 'Season Name', 'Meet Name' );

=head2 state

This method calculates the state of the meet. It does this by starting with the
C<build> data of the meet. It will then load data for every quiz at least
started/initialized for the meet, calculating team and quizzer points and
positions. If a quiz or bracket is complete, any subsequent quiz or bracket that
relies on the results is updated. (For example, if a quiz's teams consist of the
first-place teams from 3 other quizzes.)

    my $state = $meet->state;

The method will return a hashref with a structure similar to the following:

    ---
    brackets:
      - name: ...
        weight: 1
        material:
          description: ...
          id: ...
          label: ...
        sets:
          - rooms:
            - id: 1
              name: 1
              room: 1
              roster:
                - id: _0
                  name: ...
                  appeals_declined: 0
                  timeouts_remaining: 1
                  triggle_eligible: true
                  quizzers:
                    - bible: NIV
                      id: _1
                      name: ...
                      score: {}
                      tags:
                        - Veteran
                        - Youth
                  score: {}
              schedule: {}
              distribution: [{}]

=head2 quiz_settings

This method requires a bracket name and quiz name as input; it will return a
quiz settings data structure suitable for L<QuizSage::Model::Quiz> objects.

    my $quiz_settings = $meet->quiz_settings( 'Bracket Name', 'Quiz Name' );

=head2 distribution

This method primarily just returns the meet's C<build> data. However, if there
are any cases where a quiz's distribution includes Bible translations of C<?>
and the quiz has itself been build (which therefore means it has actual
translations), then the quiz's distribution is copied into the data structure
that's returned from this method.

=head2 stats

This method returns a data structure containing meet statistics.

    my $stats = $meet->stats;

The statistics hashref returned will contain keys for at least but perhaps not
limited to: C<quizzers>, C<teams>, C<rankings>, C<meta>.

=head2 admin_auth

Requires a loaded user object and will return a boolean of whether the user is
authorized as an administrator of the meet.

=head2 admin

Returns an arrayref of hashrefs of users who are administrators of the meet.

=head2 admins

Requires either "add" or "remove" followed by a user ID. Will then either add
or remove that user to/from the list of administrators of the meet.

=head2 swap_draw_parts

Swap draw parts (sets and/or quizzes) built meet's schedule. Requires the meet
object be loaded and have previously been built via C<build>. The method
requires the input of a text string of the name of the bracket to change
followed by an arrayref of sets to swap and an arrayref of quizzes to swap.


    # swap the first and fourth sets in the draw of the "Preliminary" bracket
    $meet->swap_draw_parts( 'Preliminary', [ 1, 4 ], [] );

    # swap the third and twelfth quizzes in the draw of the "Preliminary" bracket
    $meet->swap_draw_parts( 'Preliminary', [], [ 3, 12 ] );

    # swap both the sets and draws from the examples above
    $meet->swap_draw_parts( 'Preliminary', [ 1, 4 ], [ 3, 12 ] );

=head1 WITH ROLES

L<Omniframe::Role::Model>, L<QuizSage::Role::Meet::Build>,
<QuizSage::Role::Meet::Settings>, L<QuizSage::Role::Meet::Editing>.
