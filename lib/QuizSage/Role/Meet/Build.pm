package QuizSage::Role::Meet::Build;

use exact -role;
use Mojo::JSON 'decode_json';
use Omniframe::Class::Javascript;
use QuizSage::Util::Material 'material_json';
use YAML::XS 'Dump';

with qw(
    Omniframe::Role::Database
    Omniframe::Role::Time
    QuizSage::Role::Data
    QuizSage::Role::JSApp
    QuizSage::Role::Meet::Settings
);

sub build ( $self, $user_id = undef ) {
    my ($build_settings) = $self->build_settings;
    $self->create_material_json( $build_settings, $user_id );
    $self->build_bracket_data($build_settings);
    my $schedule_integration_warnings = $self->schedule_integration($build_settings);
    $self->add_distributions($build_settings);
    $self->build_settings_cleanup($build_settings);
    $self->save({ build => $build_settings });
    return $schedule_integration_warnings;
}

sub create_material_json ( $self, $build_settings, $user_id = undef ) {
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

sub build_bracket_data ( $self, $build_settings ) {
    my $bracket_names;
    $bracket_names->{ $_->{name} }++ for ( $build_settings->{brackets}->@* );
    die "Duplicate bracket names\n" if ( grep { $_ > 1 } values %$bracket_names );

    for my $bracket ( $build_settings->{brackets}->@* ) {
        my $teams;

        if ( $bracket->{teams} ) {
            $teams = ( $bracket->{teams}{source} eq 'roster' )
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
        }

        if ( $bracket->{type} eq 'score_sum' ) {
            my ($meet) = $self->build_score_sum_draw(
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
        elsif ( $bracket->{type} eq 'manual' ) {
            my @rooms;
            for my $quiz ( @{ ( $bracket->{quizzes} ) ? $bracket->{quizzes} : [ $bracket->{name} ] } ) {
                push( @rooms, {
                    name   => $quiz,
                    room   => @rooms + 1,
                    roster => [ ({}) x $bracket->{teams_count} ],
                } );

                if ( @rooms == $bracket->{rooms} ) {
                    push( @{ $bracket->{sets} }, { rooms => [@rooms] } );
                    @rooms = ();
                }
            }
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

sub schedule_integration( $self, $build_settings ) {
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
    my $events = $schedule->{events} // [];
    for my $event (@$events) {
        $event->{start} = $self->time->parse( $event->{start} )->datetime if ( $event->{start} );
        $event->{duration} //= $schedule_duration;
    }

    # data calculation
    for my $bracket ( $build_settings->{brackets}->@* ) {
        my ($source) =
            grep { $_->{name} eq ( $bracket->{teams}{source} // '' ) }
            $build_settings->{brackets}->@*;
        my $block_i = 0;
        my $pointer = (
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

    # merge sets in the same bracket that have the same start
    for my $bracket ( $build_settings->{brackets}->@* ) {
        my $i = 1;
        while ( $i < $bracket->{sets}->@* ) {
            if (
                $bracket->{sets}[$i]{rooms}[0]{schedule}{start} eq
                $bracket->{sets}[ $i - 1 ]{rooms}[0]{schedule}{start}
            ) {
                push( $bracket->{sets}[ $i - 1 ]{rooms}->@*, $bracket->{sets}[$i]{rooms}->@* );
                splice( $bracket->{sets}->@*, $i, 1 );
            }
            else {
                $i++;
            }
        }
    }

    # check that no 2 quizzes are happening at the same time in the same location
    # and check that no teams are quizzing in 2 places at the same time
    my @quizzes = map {
        my $bracket = $_->{name};
        map { +{ %$_, bracket => $bracket } } map { $_->{rooms}->@* } $_->{sets}->@*;
    } $build_settings->{brackets}->@*;

    my $warnings = [];
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
                if ( $quiz_1->{room} == $quiz_2->{room} ) {
                    my $warning =
                        $quiz_1->{bracket} . ' Quiz ' . $quiz_1->{name} .
                        ' (room ' . $quiz_1->{room} . ')' .
                        ' happens at the same time as ' .
                        $quiz_2->{bracket} . ' Quiz ' . $quiz_2->{name} .
                        ' (room ' . $quiz_1->{room} . ')';
                    $self->warn( $warning . "\n" );
                    push( @$warnings, $warning );
                }

                my @teams_quiz_1 = grep { length > 1 } map {
                    $_->{name} // ( $_->{bracket} // $_->{quiz} // '' ) . ' ' . ( $_->{position} // '' )
                } $quiz_1->{roster}->@*;

                for my $team_quiz_2 ( grep { length > 1 } map {
                    $_->{name} // ( $_->{bracket} // $_->{quiz} // '' ) . ' ' . ( $_->{position} // '' )
                } $quiz_2->{roster}->@* ) {
                    if ( grep { $team_quiz_2 eq $_ } @teams_quiz_1 ) {
                        my $warning =
                            $team_quiz_2 . ' is in ' .
                            $quiz_1->{bracket} . ' Quiz ' . $quiz_1->{name} .
                            ' (room ' . $quiz_1->{room} . ')' .
                            ' and ' .
                            $quiz_2->{bracket} . ' Quiz ' . $quiz_2->{name} .
                            ' (room ' . $quiz_1->{room} . ')' .
                            ', which are at the same time';
                        $self->warn( $warning . "\n" );
                        push( @$warnings, $warning );
                    }
                }
            }
        }
    }

    # datetime formatting
    for my $bracket ( $build_settings->{brackets}->@* ) {
        for my $set ( $bracket->{sets}->@* ) {
            for my $quiz ( $set->{rooms}->@* ) {
                for ( qw( start stop ) ) {
                    if ( $quiz->{schedule}{$_} ) {
                        $self->time->datetime( $quiz->{schedule}{$_} );
                        $quiz->{schedule}{$_} = $self->time->format('sqlite_min');
                    }
                }
            }
        }
    }
    if ( $events->@* ) {
        for my $event ( $events->@* ) {
            for ( qw( start stop ) ) {
                if ( $event->{$_} ) {
                    $self->time->datetime( $event->{$_} );
                    $event->{$_} = $self->time->format('sqlite_min');
                }
            }
        }
        $build_settings->{events} = $events;
    }

    return $warnings;
}

sub build_score_sum_draw (
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

sub add_distributions ( $self, $build_settings ) {
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

sub build_settings_cleanup( $self, $build_settings ) {
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

=head2 create_material_json

This method requires build settings (as provided by C<build_settings> from
L<QuizSage::Role::Meet::Settings>) and an optional user ID. It will then run
C<material_json> from L<QuizSage::Util::Material> to build material JSON. In
doing so, it'll replace bracket C<material> nodes with the C<material> result
returned from C<material_json>.

    my ($build_settings) = $self->build_settings;
    $self->create_material_json( $build_settings, 42 );

=head2 build_bracket_data

This method will build bracket data. It requires build settings and returns
nothing.

=head2 schedule_integration

This method requires build settings, and it will use and remove C<schedule> node
data, integrating it into brackets. It will return an arrayref of any warnings
derived from the integration process (i.e. time conflicts).

=head2 build_score_sum_draw

This method is more of a function. It requires an arrayref of team names plus
optionally number of rooms, quizzes per team, and a boolean as to whether to
randomize the draw. The method then builds the draw and returns the meet draw
along with team and quiz statistics about the draw.

    my ( $meet, $team_stats, $quiz_stats ) = $self->build_score_sum_draw(
        [ qw( team1 team2 team3 ... ) ],
        4, # 4 rooms at the meet
        6, # 6 quizzes per team
        1, # randomize
    );

=head2 add_distributions

This method adds distributions into build settings. It requires build settings
and returns nothing.

=head2 build_settings_cleanup

This method cleans up build settings.

=head1 WITH ROLES

L<Omniframe::Role::Database>, L<Omniframe::Role::Time>, L<QuizSage::Role::Data>,
L<QuizSage::Role::JSApp>, L<QuizSage::Role::Meet::Settings>.
