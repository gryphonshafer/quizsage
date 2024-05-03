package QuizSage::Role::Meet::Build;

use exact -role;
use Mojo::JSON 'decode_json';
use Omniframe::Class::Javascript;
use Omniframe::Util::Text 'trim';
use QuizSage::Model::Season;
use QuizSage::Util::Material 'material_json';
use YAML::XS 'Dump';

with qw(
    Omniframe::Role::Database
    Omniframe::Role::Time
    QuizSage::Role::Data
    QuizSage::Role::JSApp
);

sub build ( $self, $user_id = undef ) {
    my $build_settings = $self->_merge_meet_and_season_settings;
    $self->parse_and_structure_roster_text( \$build_settings->{roster} );
    $self->_create_material_json( $build_settings, $user_id );
    $self->_build_bracket_data($build_settings);
    $self->_schedule_integration($build_settings);
    $self->_add_distributions($build_settings);
    $self->_build_settings_cleanup($build_settings);
    $self->save({ build => $build_settings });
    return;
}

sub _merge_meet_and_season_settings ($self) {
    my $meet_settings   = $self->deepcopy( $self->data->{settings} // {} );
    my $season_settings =
        QuizSage::Model::Season->new->load( $self->data->{season_id} )->data->{settings} // {};

    my $build_settings;

    ( $build_settings->{brackets} ) = grep { defined }
        delete $meet_settings->{brackets}, delete $season_settings->{brackets}, [];

    for my $set ( $season_settings, $meet_settings ) {
        for ( keys %{ $set->{roster} } ) {
            ( $build_settings->{roster}{$_} ) = delete $set->{roster}{$_}
                if ( $set->{roster}{$_} );
        }
        delete $set->{roster};
        $build_settings->{schedule} = delete $set->{schedule} if ( $set->{schedule} );
        $build_settings->{per_quiz}->{$_} = delete $set->{$_} for ( keys %$set );
    }

    return $build_settings;
}

sub parse_and_structure_roster_text ( $self, $roster_ref ) {
    my $default_bible = delete $$roster_ref->{default_bible} // $self->conf->get( qw( quiz_defaults bible ) );

    my @bible_acronyms = $self->dq('material')->get(
        'bible',
        ['acronym'],
        undef,
        { order_by => [ { -desc => { -length => 'acronym' } }, 'acronym' ] },
    )->run->column;

    my $bibles_re = '\b(?:' . join( '|', @bible_acronyms ) . ')\b';

    my $tags    = delete $$roster_ref->{tags} // {};
    $tags->{$_} = ( ref $tags->{$_} ) ? $tags->{$_} : [ $tags->{$_} ] for ( qw( append default ) );

    my $parse_out_bibles_and_tags = sub ($text_ref) {
        $$text_ref =~ s/\s+/ /g;

        my $bible;
        if (@bible_acronyms) {
            $bible //= $1 while ( $$text_ref =~ s/($bibles_re)//i );
        }

        my @tags;
        push( @tags, split( /\s*[,;]+\s*/, $1 ) ) while ( $$text_ref =~ s/\(([^\)]*)\)//i );

        $$text_ref =~ s/\s+/ /g;
        $$text_ref =~ s/^\s|\s$//g;

        return $bible, (@tags) ? \@tags : undef;
    };

    $$roster_ref = [
        map {
            my ( $team_name,  @quizzers  ) = split(/\r?\n\s*/);
            my ( $team_bible, $team_tags ) = $parse_out_bibles_and_tags->( \$team_name );

            +{
                name     => $team_name,
                quizzers => [
                    map {
                        my $quizzer = $_;
                        my ( $quizzer_bible, $quizzer_tags ) = $parse_out_bibles_and_tags->( \$quizzer );

                        $quizzer_tags //= $team_tags // $tags->{default} // [];
                        $quizzer_tags = [@$quizzer_tags];
                        push( @$quizzer_tags, $tags->{append}->@* );
                        my %quizzer_tags = map { $_ => 1 } grep { defined } @$quizzer_tags;
                        $quizzer_tags = [ sort keys %quizzer_tags ];

                        +{
                            name       => $quizzer,
                            bible      => $quizzer_bible // $team_bible // $default_bible,
                            maybe tags => ( (@$quizzer_tags) ? $quizzer_tags : undef ),
                        };
                    } @quizzers
                ],
            };
        } split( /\n\s*\n/, delete $$roster_ref->{data} )
    ];

    return;
}

sub _create_material_json ( $self, $build_settings, $user_id = undef ) {
    for my $set (
        ( $build_settings->{per_quiz} // undef ),
        $build_settings->{brackets}->@*,
    ) {
        next unless ( $set and defined $set->{material} );

        my $label = $set->{material};
        $set->{material} = material_json(
            label      => $label,
            maybe user => $user_id,
        );
        $set->{material}{label} = $label;
    }
}

sub _build_bracket_data ( $self, $build_settings ) {
    my $bracket_names;
    $bracket_names->{ $_->{name} }++ for ( $build_settings->{brackets}->@* );
    die "Duplicate bracket names\n" if ( grep { $_ > 1 } values %$bracket_names );

    for my $bracket ( $build_settings->{brackets}->@* ) {
        my $teams = ( $bracket->{teams}{source} eq 'roster' )
            ? $build_settings->{roster}
            : [
                map {
                    +{
                        position => $_,
                        bracket  => $bracket->{teams}{source},
                    };
                } (
                    1 .. (
                        grep { $bracket->{teams}{source} eq $_->{name} } $build_settings->{brackets}->@*
                    )[0]->{teams}{derived_count} // scalar( @{ $build_settings->{roster} } )
                )
            ];

        $teams = [ @$teams[
            ( ( $bracket->{teams}{places}{min} ) ? $bracket->{teams}{places}{min} - 1 : 0 )
            ..
            ( ( $bracket->{teams}{places}{max} ) ? $bracket->{teams}{places}{max} - 1 : @$teams - 1 )
        ] ] if ( $bracket->{teams}{places} );

        $bracket->{teams}{derived_count} = @$teams;

        if ( $bracket->{teams}{slotting} ) {
            if ( ( $bracket->{teams}{slotting} // '' ) eq 'random' ) {
                $teams = [ map { $_->[0] } sort { $a->[1] <=> $b->[1] } map { [ $_, rand ] } @$teams ];
            }
            elsif ( ( $bracket->{teams}{slotting} // '' ) eq 'striped' ) {
                my %queues;
                push( @{ $queues{ $_ % $bracket->{rooms} } }, $teams->[$_] ) for ( 0 .. @$teams - 1 );
                $teams = [ map { $queues{$_}->@* } sort { $a <=> $b } keys %queues ];
            }
            elsif ( ( $bracket->{teams}{slotting} // '' ) eq 'snaked' ) {
                my %queues;
                push( @{ $queues{
                    ( $_ / $bracket->{rooms} % 2 )
                        ? abs( $_ % $bracket->{rooms} - ( $bracket->{rooms} - 1 ) )
                        : $_ % $bracket->{rooms}
                } }, $teams->[$_] ) for ( 0 .. @$teams - 1 );
                $teams = [ map { $queues{$_}->@* } sort { $a <=> $b } keys %queues ];
            }
        }

        if ( $bracket->{type} eq 'score_sum' ) {
            my ($meet) = $self->_build_score_sum_draw(
                $teams,
                $bracket->{rooms},
                $bracket->{quizzes_per_team},
            );

            my $name;
            $bracket->{sets} = [
                map {
                    my $room;
                    +{
                        rooms => [
                            map {
                                +{
                                    name   => ++$name,
                                    room   => ++$room,
                                    roster => $_,
                                };
                            } @$_,
                        ],
                    };
                } @$meet
            ];
        }
        elsif ( $bracket->{type} eq 'positional' ) {
            my $template = $self->dataload( 'config/meets/brackets/' . $bracket->{template} . '.yaml' );

            for my $quiz_override ( $bracket->{quizzes}->@* ) {
                my ($quiz_to_override) =
                    grep { $quiz_override->{name} eq $_->{name} } $template->{quizzes}->@*;
                $quiz_to_override->{$_} = $quiz_override->{$_} for ( keys %$quiz_override );
            }

            for ( grep { not exists $_->{roster} } $template->{quizzes}->@* ) {
                push( @{ $_->{roster} }, shift @$teams ) while ( @$teams and @{ $_->{roster} // [] } < 3 );
            }

            my ( $current_set, $current_room );
            my $push_set = sub {
                push( @{ $bracket->{sets} }, { rooms => $current_set } );
                $current_room = 1;
                $current_set  = [];
            };
            while ( my $quiz = shift $template->{quizzes}->@* ) {
                $current_room++;

                $push_set->() if (
                    $current_room > $bracket->{rooms}
                    or do {
                        my @current_set_quiz_names = map { $_->{name} } $current_set->@*;
                        scalar grep {
                            my $this_name = $_->{quiz};
                            grep { $this_name and $this_name eq $_ } @current_set_quiz_names;
                        } $quiz->{roster}->@*;
                    }
                );

                $quiz->{room} = $current_room;
                push( @$current_set, $quiz );
            }
            $push_set->();

            $bracket->{rankings} = $template->{rankings};
        }

        my $quiz_names;
        $quiz_names->{ $_->{name} }++ for ( map { $_->{rooms}->@* } $bracket->{sets}->@* );
        die "Duplicate quiz names\n" if ( grep { $_ > 1 } values %$quiz_names );
    }

    return;
}

sub _schedule_integration( $self, $build_settings ) {
    my $schedule          = delete $build_settings->{schedule} // {};
    my $schedule_duration = $schedule->{duration} // $self->conf->get( qw( quiz_defaults duration ) );

    # blocks setup
    my $blocks;
    unless ( $schedule->{blocks} and $schedule->{blocks}->@* ) {
        $blocks = [ {
            start    => $self->time->parse( $self->data->{start} )->datetime,
            duration => $schedule_duration,
        } ];
    }
    else {
        $blocks = $self->deepcopy( $schedule->{blocks} );
        for my $block (@$blocks) {
            $block->{start} = $self->time->parse( $block->{start} )->datetime if ( $block->{start} );
            $block->{stop}  = $self->time->parse( $block->{stop}  )->datetime if ( $block->{stop}  );

            $block->{duration} //= $schedule_duration;
        }
    }

    # events setup
    my $events = $schedule->{events} // {};
    for my $event (@$events) {
        $event->{start} = $self->time->parse( $event->{start} )->datetime if ( $event->{start} );
        $event->{duration} //= $schedule_duration;
    }

    # data calculation
    for my $bracket ( $build_settings->{brackets}->@* ) {
        my ($source) = grep { $_->{name} eq $bracket->{teams}{source} } $build_settings->{brackets}->@*;
        my $block_i  = 0;
        my $pointer  = (
            ($source)
                ? $source->{sets}[-1]{rooms}[0]{schedule}{stop}
                : $blocks->[$block_i]->{start}
        )->clone;

        # events able to have start and stop determined without set times get those determined
        for my $event ( grep { not $_->{before} and not $_->{after} and not $_->{stop} } @$events ) {
            $event->{start} = $pointer->clone if ( not $event->{start} );
            $event->{stop}  = $event->{start}->clone->add( minutes => $event->{duration} );
        }

        my ($bracket_overrides) = reverse grep {
            not $_->{quiz} and
            $_->{bracket} eq $bracket->{name}
        } $schedule->{overrides}->@*;

        for my $set ( $bracket->{sets}->@* ) {
            my $determine_event_start_and_stop = sub ($type) {
                for my $event ( grep {
                    $_->{$type} and not $_->{stop} and (
                        ref $_->{$type} and $_->{$type}[0] eq $bracket->{name} or
                        $type eq 'before' and not ref $_->{$type} and $_->{$type} eq $bracket->{name}
                    )
                } @$events ) {
                    next if (
                        ref $event->{$type} and
                        not grep { $event->{$type}[1] eq $_->{name} } $set->{rooms}->@*
                    );
                    $event->{start} = $pointer->clone if ( not $event->{start} );
                    $event->{stop}  = $event->{start}->clone->add( minutes => $event->{duration} );
                }
            };

            # if an event is before this set, determine event's start/stop
            $determine_event_start_and_stop->('before');

            my $set_duration =
                ( ($bracket_overrides) ? $bracket_overrides->{duration} : undef ) //
                $blocks->[$block_i]->{duration} //
                $schedule_duration;

            my $set_start = $pointer->clone;
            my $set_stop  = $pointer->add( minutes => $set_duration )->clone;

            my $push_down_set_start_stop_if_an_event_conflicts = sub {
                while (
                    my ($latest_stop) =
                        map { $_->[0] }
                        sort { $b->[1] <=> $a->[1] }
                        map { [ $_->{stop}, $_->{stop}->epoch ] }
                        grep {
                            $_->{start} and $_->{stop} and
                            not (
                                $_->{stop}->epoch <= $set_start->epoch or
                                $set_stop->epoch <= $_->{start}->epoch
                            )
                        }
                        @$events
                ) {
                    $set_start = $latest_stop->clone;
                    $set_stop  = $latest_stop->clone->add( minutes => $set_duration );
                    $pointer   = $set_stop->clone;
                }
            };

            $push_down_set_start_stop_if_an_event_conflicts->();

            # handle time block boundaries
            while (
                $block_i < @$blocks and
                $blocks->[$block_i]->{stop} and
                $set_stop->epoch > $blocks->[$block_i]->{stop}->epoch
            ) {
                $block_i++;
                if ( $blocks->[$block_i]->{start}->epoch > $pointer->epoch ) {
                    $pointer   = $blocks->[$block_i]->{start}->clone;
                    $set_start = $pointer->clone;
                    $set_stop  = $pointer->add( minutes => $set_duration )->clone;
                }
            }

            $push_down_set_start_stop_if_an_event_conflicts->();

            # if an event is after this set, determine event's start/stop
            $determine_event_start_and_stop->('after');

            for my $quiz ( $set->{rooms}->@* ) {
                my ( $start, $duration, $stop ) = ( $set_start->clone, $set_duration, $set_stop->clone );

                # handle explicit overrides
                for my $override (
                    grep {
                        (
                            not $_->{bracket} or
                            not ref $_->{bracket} and $bracket->{name} eq $_->{bracket} or
                            ref $_->{bracket} and grep { $bracket->{name} eq $_ } $_->{bracket}->@*
                        ) and
                        (
                            not $_->{quiz} or
                            not ref $_->{quiz} and $quiz->{name} eq $_->{quiz} or
                            ref $_->{quiz} and grep { $quiz->{name} eq $_ } $_->{quiz}->@*
                        )
                    } $schedule->{overrides}->@*
                ) {
                    $start    = $self->time->parse( $override->{start} )->datetime if ( $override->{start} );
                    $duration = ( $override->{duration} ) ? $override->{duration} : $set_duration;
                    $stop     = $start->clone->add( minutes => $duration );

                    $quiz->{room} = $override->{room} if ( $override->{room} );
                }

                @{ $quiz->{schedule} }{ qw( start duration stop ) } = ( $start, $duration, $stop );
            }
        }

        for my $event ( grep {
            $_->{after} and not $_->{stop} and
            not ref $_->{after} and $_->{after} eq $bracket->{name}
        } @$events ) {
            $event->{start} = (
                $bracket->{sets}[-1]{rooms}[-1]{schedule}{stop} // $pointer
            )->clone if ( not $event->{start} );

            $event->{stop} = $event->{start}->clone->add( minutes => $event->{duration} );
        }
    }

    # data formatting
    for my $bracket ( $build_settings->{brackets}->@* ) {
        for my $set ( $bracket->{sets}->@* ) {
            for my $quiz ( $set->{rooms}->@* ) {
                $quiz->{schedule}{date} = trim( $quiz->{schedule}{start}->strftime('%a, %b %e') );
                for ( qw( start stop ) ) {
                    $quiz->{schedule}{ $_ . '_time' } = trim( $quiz->{schedule}{$_}->strftime('%l:%M %p') );
                    $quiz->{schedule}{$_} = $quiz->{schedule}{$_}->epoch;
                }
            }
        }
    }
    if ( $events->@* ) {
        for my $event ( $events->@* ) {
            $event->{date} = trim( ( $event->{start} // $event->{stop} )->strftime('%a, %b %e') )
                if ( $event->{start} or $event->{stop} );
            if ( $event->{start} ) {
                $event->{start_time} = trim( $event->{start}->strftime('%l:%M %p') );
                $event->{start}      = $event->{start}->epoch;
            }
            if ( $event->{stop} ) {
                $event->{stop_time} = trim( $event->{stop}->strftime('%l:%M %p') );
                $event->{stop}      = $event->{stop}->epoch;
            }
        }
        $build_settings->{events} = $events;
    }

    # check that no 2 quizzes are happening at the same time in the same location
    # and check that no teams are quizzing in 2 places at the same time
    my @quizzes = map {
        my $bracket = $_->{name};
        map { +{ %$_, bracket => $bracket } } map { $_->{rooms}->@* } $_->{sets}->@*;
    } $build_settings->{brackets}->@*;

    while ( my $quiz_1 = shift @quizzes ) {
        for my $quiz_2 (@quizzes) {
            my ( $quiz_1_start, $quiz_1_stop, $quiz_2_start, $quiz_2_stop ) = (
                $quiz_1->{schedule}{start},
                $quiz_1->{schedule}{stop},
                $quiz_2->{schedule}{start},
                $quiz_2->{schedule}{stop},
            );

            if (
                $quiz_1_start >= $quiz_2_start and $quiz_1_start < $quiz_2_stop  or
                $quiz_1_stop  <= $quiz_2_stop  and $quiz_1_stop  > $quiz_2_start or
                $quiz_2_start >= $quiz_1_start and $quiz_2_start < $quiz_1_stop  or
                $quiz_2_stop  <= $quiz_1_stop  and $quiz_2_stop  > $quiz_1_start
            ) {
                warn(
                    $quiz_1->{bracket} . ' Quiz ' . $quiz_1->{name} . ' (room ' . $quiz_1->{room} . ')' .
                    ' happens at the same time as ' .
                    $quiz_2->{bracket} . ' Quiz ' . $quiz_2->{name} . ' (room ' . $quiz_1->{room} . ')' . "\n"
                ) if ( $quiz_1->{room} == $quiz_2->{room} );

                my @teams_quiz_1 = map {
                    $_->{name} // ( $_->{bracket} // $_->{quiz} ) . ' ' . $_->{position}
                } $quiz_1->{roster}->@*;
                for my $team_quiz_2 ( map {
                    $_->{name} // ( $_->{bracket} // $_->{quiz} ) . ' ' . $_->{position}
                } $quiz_2->{roster}->@* ) {
                    warn(
                        $team_quiz_2 . ' is in ' .
                        $quiz_1->{bracket} . ' Quiz ' . $quiz_1->{name} . ' (room ' . $quiz_1->{room} . ')' .
                        ' and ' .
                        $quiz_2->{bracket} . ' Quiz ' . $quiz_2->{name} . ' (room ' . $quiz_1->{room} . ')' .
                        ', which are at the same time' . "\n"
                    ) if ( grep { $team_quiz_2 eq $_ } @teams_quiz_1 );
                }
            }
        }
    }

    return;
}

sub _build_score_sum_draw (
    $self,
    $teams,
    $rooms            = 1,
    $quizzes_per_team = 6,
    $no_random        = 0,
) {
    my $team_id               = 0;
    my $teams_matrix          = [ map { { name => $_, id => $team_id++ } } @$teams ];
    my $skip_room_sort_matrix = {
        3 => [ 10 ],
        5 => [ 14, 16, 21 ],
        6 => [ 5, 11, 18 ],
    };

    my $skip_room_sort_on = ( @$teams / $rooms == int( @$teams / $rooms ) )
        ? $skip_room_sort_matrix->{$rooms}
        : [];

    $teams_matrix = [
        map { $_->[0] } sort { $a->[1] <=> $b->[1] } map { [ $_, rand ] } @$teams_matrix
    ] unless ($no_random);

    # calculate quiz counts
    my $remainder = @$teams_matrix * $quizzes_per_team % 3;
    my $three_team_quizzes = int( @$teams_matrix * $quizzes_per_team / 3 );
    $three_team_quizzes-- if ( $remainder == 1 );
    my $two_team_quizzes = ( $remainder == 1 ) ? 2 : ( $remainder == 2 ) ? 1 : 0;

    # generate meet schema
    my ( $meet, @quizzes );
    for ( 1 .. $three_team_quizzes + $two_team_quizzes ) {
        my $set = [];
        for ( 1 .. $rooms ) {
            my $quiz = [ (undef) x 3 ];
            push( @$set, $quiz );
            push( @quizzes, $quiz );
            last if ( @quizzes >= $three_team_quizzes + $two_team_quizzes );
        }
        push( @$meet, $set );
        last if ( @quizzes >= $three_team_quizzes + $two_team_quizzes );
    }
    if ($two_team_quizzes) {
        @quizzes = map { $_->[0] } sort { $a->[1] <=> $b->[1] } map { [ $_, rand ] } @quizzes
            unless ($no_random);

        pop @{ $quizzes[$_] } for ( 0 .. $two_team_quizzes - 1 );
    }

    my $set_count = 0;
    for my $set (@$meet) {
        $set_count++;
        my @already_scheduled_teams;
        for my $room ( 1 .. $rooms ) {
            my $quiz = $set->[ $room - 1 ];
            next unless $quiz;
            for my $position ( 0 .. @$quiz - 1 ) {
                my @available_teams = grep {
                    my $team = $_;
                    not grep { $team->{id} == $_->{id} } @already_scheduled_teams;
                } @$teams_matrix;

                die "Insufficient teams to fill quiz set; reduce rooms or rerun\n" unless @available_teams;

                my @quiz_team_names = map { $_->{name} } grep { defined } @$quiz;
                if (@quiz_team_names) {
                    for my $team (@available_teams) {
                        $team->{seen_team_weight} = 0;
                        $team->{seen_team_weight} += $team->{teams}{$_} || 0 for (@quiz_team_names);
                    }
                }

                my ($selected_team) = sort {
                    ( $a->{quizzes}          || 0 ) <=> ( $b->{quizzes}          || 0 ) ||
                    ( $a->{seen_team_weight} || 0 ) <=> ( $b->{seen_team_weight} || 0 ) ||
                    (
                        ( grep { $set_count == $_ } @$skip_room_sort_on )
                            ? 0
                            : ( $a->{rooms}{$room} || 0 ) <=> ( $b->{rooms}{$room} || 0 )
                    ) ||
                    ( $a->{positions}{$position} || 0 ) <=> ( $b->{positions}{$position} || 0 ) ||
                    $a->{id} <=> $b->{id}
                } @available_teams;

                die "Unable to select a team via algorithm; reduce rooms or rerun\n" unless $selected_team;

                $quiz->[$position] = $selected_team;
                push( @already_scheduled_teams, $selected_team );

                $selected_team->{rooms}{$room}++;
                $selected_team->{positions}{$position}++;
                $selected_team->{quizzes}++;
            }

            my @quiz_team_names = map { $_->{name} } @$quiz;
            for my $team (@$quiz) {
                $team->{teams}{$_}++ for ( grep { $team->{name} ne $_ } @quiz_team_names );
            }
        }
    }

    unless ($no_random) {
        # randomize sets
        my $last_set = pop @$meet;
        $meet = [ ( map { $_->[0] } sort { $a->[1] <=> $b->[1] } map { [ $_, rand ] } @$meet ), $last_set ];

        # randomize the rooms
        my $room_map;
        for my $set ( grep { defined } @$meet ) {
            $room_map //= [ map { $_->[0] } sort { $a->[1] <=> $b->[1] } map { [ $_ - 1, rand ] } 1 .. @$set ];
            next unless ( @$set == @$room_map );
            $set = [ map { $set->[ $room_map->[$_] ] } ( 0 .. @$room_map - 1 ) ];
        }
    }

    my $quiz_counts;
    for my $set (@$meet) {
        for my $quiz (@$set) {
            # clean meet data set
            $quiz = [ map { $_->{name} } @$quiz ];

            my $quiz_key = join( '', sort @$quiz );
            $quiz_counts->{$quiz_key}{count}++;
            $quiz_counts->{$quiz_key}{quiz} = $quiz;
        }
    }

    my $quiz_stats;
    for my $quiz_key ( sort keys %$quiz_counts ) {
        push( @{ $quiz_stats->{ $quiz_counts->{$quiz_key}{count} } }, $quiz_counts->{$quiz_key}{quiz} );
    }

    my $team_stats = [
        sort { $a->{name} cmp $b->{name} }
        map {
            my $team    = $_;
            my $quizzes = 0;
            my $rooms   = { map {
                $quizzes += $team->{rooms}{$_};
                $_ + 1 => $team->{rooms}{$_};
            } keys %{ $team->{rooms} } };

            +{
                name    => $team->{name},
                rooms   => $rooms,
                teams   => \%{ $team->{teams} },
                quizzes => $quizzes,
            };
        } @$teams_matrix
    ];

    return $meet, $team_stats, $quiz_stats;
}

sub _add_distributions ( $self, $build_settings ) {
    my ( $material_json_bibles, $importmap_js );

    my $root_dir = $self->conf->get( qw( config_app root_dir ) );

    for my $bracket ( $build_settings->{brackets}->@* ) {
        for my $quiz ( map { $_->{rooms}->@* } $bracket->{sets}->@* ) {
            my $material =
                $quiz->{material} ||
                $bracket->{material} ||
                ( $build_settings->{per_quiz} // {} )->{material};

            $material_json_bibles->{ $material->{json_file}->to_string } //= do {
                my $bibles = decode_json( $material->{json_file}->slurp )->{bibles};
                [ grep { $bibles->{$_}{type} eq 'primary' } keys %$bibles ];
            };

            my $importmap =
                $quiz->{importmap} ||
                $bracket->{importmap} ||
                ( $build_settings->{per_quiz} // {} )->{importmap} ||
                $self->js_app_config(
                    'quiz',
                    $quiz->{js_apps_id} ||
                    $bracket->{js_apps_id} ||
                    ( $build_settings->{per_quiz} // {} )->{js_apps_id},
                )->{importmap};

            my $importmap_yaml = Dump($importmap);

            $importmap_js->{$importmap_yaml} //= Omniframe::Class::Javascript->new(
                basepath  => $root_dir . '/static/js',
                importmap => $importmap,
            );

            $quiz->{distribution} = $importmap_js->{$importmap_yaml}->run(
                $root_dir . '/ocjs/lib/Model/Meet/distribution.js',
                {
                    bibles      => $material_json_bibles->{ $material->{json_file}->to_string },
                    teams_count => scalar( $quiz->{roster}->@* ),
                },
            )->[0][0];
        }
    }

    return;
}

sub _build_settings_cleanup( $self, $build_settings ) {
    delete $build_settings->{per_quiz}{material}{json_file}
        if ( ( $build_settings->{per_quiz} // {} )->{material} );
    for my $bracket ( $build_settings->{brackets}->@* ) {
        delete $bracket->{$_} for ( qw( quizzes_per_team rooms teams template type quizzes ) );
        delete $bracket->{material}{json_file} if ( $bracket->{material} );
        delete $_->{material}{json_file}
            for ( grep { $_->{material} } map { $_->{rooms}->@* } $bracket->{sets}->@* );
    }
    return;
}

1;

=head1 NAME

QuizSage::Role::Meet::Build

=head1 SYNOPSIS

    package Package;

    use exact -class;

    with 'QuizSage::Role::Meet::Build';

=head1 DESCRIPTION

This role provides some meet build methods. In particular, it provides C<build>
to build meets, which itself calls C<parse_and_structure_roster_text> as part of
it's process to build a meet.

=head1 METHODS

=head2 build

Thie method will build a meet, populating the C<build> JSON data of a meet
database record. The method may optionally accept a user ID, which if provided,
will be internally passed to L<QuizSage::Util::Material>'s C<material_json>
when building any needed material JSON files for the meet.

The C<build> method will internally conduct the following, in order:

=over

=item * Merge meet and season settings

=item * Parse and structure roster text (via a call to
C<parse_and_structure_roster_text>)

=item * Create material JSON

=item * Build bracket data

=item * Schedule integration

=item * Add distributions

=item * Build settings cleanup

=item * Save the build settings to the C<build> field of the meet's database row

=back

=head2 parse_and_structure_roster_text

This method requires a reference to a hashref. (Yes, a reference to a
reference.) The hashref itself must have a C<data> key, which is a string of
text. The hashref may also have C<default_bible> and C<tags> keys/values.

    my $roster_data = {
        data          => '...',
        default_bible => 'NIV',
        tags          => {},
    };
    $obj->parse_and_structure_roster_text( \$roster_data );

The C<tags> hashref may have keys of C<default> (to represent any default tags
to apply to all quizzers) and/or C<append> (to contain any tags to append to all
quizzers). For example:

    ---
    default:
      - Veteran
    append:
      - Youth

The required C<data> string is a single string with line breaks between teams,
each team's name being the first item in a paragraph, and each quizzer being a
line following a team's name. It's possible to optionally add a Bible
translation after either a team or quizzer. Specific tags for quizzers can be
appended in parentheses. For example:

    Team 1
    Alpha Bravo
    Charlie Delta
    Echo Foxtrox

    Team 2 NASB5
    Gulf Hotel
    Juliet India NASB (Rookie)
    Kilo Lima (Rookie)

    Team 3
    Mike November
    Oscar Papa (Rookie)
    Romeo Quebec

The method will parse and structure the roster text, changing the reference from
pointing to a hashref to pointing to an array with the following structure:

    ---
    - name: Team 2
      quizzers:
        - bible: NASB5
          name:  Gulf Hotel
          tags:  [ 'Veteran', 'Youth' ]
        - bible: NASB
          name:  uliet India
          tags:  [ 'Rookie', 'Youth' ]
        - bible: NASB5
          name:  Kilo Lima
          tags:  [ 'Rookie', 'Youth' ]

=head1 WITH ROLE

L<Omniframe::Role::Time>, L<QuizSage::Role::Data>, L<QuizSage::Role::JSApp>.
