package QuizSage::Model::Meet;

use exact -class;
use Mojo::JSON qw( encode_json decode_json );
use Omniframe::Class::Javascript;
use QuizSage::Model::Meet;
use QuizSage::Util::Material 'material_json';
use YAML::XS qw( LoadFile Load Dump );

with qw( Omniframe::Role::Bcrypt Omniframe::Role::Model Omniframe::Role::Time );

my $min_passwd_length = 8;

sub validate ( $self, $data ) {
    if ( $data->{start} ) {
        my $dt = $self->time->parse( $data->{start}, 'local' );
        $data->{start} =
            $dt->strftime( $self->time->formats->{ansi} ) .
            $self->time->format_offset( $dt->offset );
    }

    $data->{settings} = LoadFile(
        $self->conf->get( qw( config_app root_dir ) ) . '/config/defaults/meet.yaml'
    ) unless ( defined $data->{settings} );

    return $data;
};

sub freeze ( $self, $data ) {
    if ( $data->{passwd} ) {
        croak("Password supplied is not at least $min_passwd_length characters in length")
            unless ( length $data->{passwd} >= $min_passwd_length );
        $data->{passwd} = $self->bcrypt( $data->{passwd} );
    }

    for ( qw( settings build ) ) {
        $data->{$_} = encode_json( $data->{$_} ) if ( defined $data->{$_} );
    }
    return $data;
}

sub thaw ( $self, $data ) {
    for ( qw( settings build ) ) {
        $data->{$_} = decode_json( $data->{$_} ) if ( defined $data->{$_} );
    }
    return $data;
}

sub build ( $self, $user_id = undef ) {
    my $build_settings = $self->_merge_meet_and_season_settings;
    $self->_parse_and_structure_roster_text( \$build_settings->{roster} );
    $self->_create_material_json( $build_settings, $user_id );
    $self->_build_bracket_data($build_settings);
    $self->_add_distributions($build_settings);
    $self->_build_settings_cleanup($build_settings);
    $self->save({ build => $build_settings });
    return;
}

sub _merge_meet_and_season_settings ($self) {
    my $meet_settings   = Load( Dump( $self->data->{settings} // {} ) );
    my $season_settings =
        QuizSage::Model::Season->new->load( $self->data->{season_id} )->data->{settings} // {};

    my $build_settings;

    ( $build_settings->{brackets} ) = grep { defined }
        delete $meet_settings->{brackets}, delete $season_settings->{brackets}, [];

    for my $set ( $season_settings, $meet_settings ) {
        ( $build_settings->{roster}{$_} ) = delete $set->{roster}{$_} for ( keys %{ $set->{roster} } );
        delete $set->{roster};
        $build_settings->{per_quiz}->{$_} = delete $set->{$_} for ( keys %$set );
    }

    return $build_settings;
}

sub _parse_and_structure_roster_text ( $self, $roster_ref ) {
    my $default_bible = delete $$roster_ref->{default_bible} // $self->conf->get('default_bible');
    my $bibles_re     = '\b(?:' . join( '|', $self->dq('material')->get(
        'bible',
        ['acronym'],
        undef,
        { order_by => [ { -desc => { -length => 'acronym' } }, 'acronym' ] },
    )->run->column ) . ')\b';

    my $tags    = delete $$roster_ref->{tags} // {};
    $tags->{$_} = ( ref $tags->{$_} ) ? $tags->{$_} : [ $tags->{$_} ] for ( qw( append default ) );

    my $parse_out_bibles_and_tags = sub ($text_ref) {
        $$text_ref =~ s/\s+/ /g;

        my $bible;
        $bible //= $1 while ( $$text_ref =~ s/($bibles_re)//i );

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
                team     => $team_name,
                quizzers => [
                    map {
                        my $quizzer = $_;
                        my ( $quizzer_bible, $quizzer_tags ) = $parse_out_bibles_and_tags->( \$quizzer );

                        $quizzer_tags //= $team_tags // $tags->{default} // [];
                        $quizzer_tags = [@$quizzer_tags];
                        push( @$quizzer_tags, $tags->{append}->@* );
                        my %quizzer_tags = map { $_ => 1 } @$quizzer_tags;
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
    for my $set ( $build_settings->{per_quiz}, $build_settings->{brackets}->@* ) {
        next unless ( defined $set->{material} );

        my $label = $set->{material};
        $set->{material} = material_json(
            label      => $label,
            maybe user => $user_id,
        );
        $set->{material}{label} = $label;
    }
}

sub _build_bracket_data ( $self, $build_settings ) {
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
            if ( $bracket->{teams}{slotting} // '' eq 'random' ) {
                $teams = [ map { $_->[0] } sort { $a->[1] <=> $b->[1] } map { [ $_, rand ] } @$teams ];
            }
            elsif ( $bracket->{teams}{slotting} // '' eq 'striped' ) {
                my %queues;
                push( @{ $queues{ $_ % $bracket->{rooms} } }, $teams->[$_] ) for ( 0 .. @$teams - 1 );
                $teams = [ map { $queues{$_}->@* } sort { $a <=> $b } keys %queues ];
            }
            elsif ( $bracket->{teams}{slotting} // '' eq 'snaked' ) {
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
            my $template = LoadFile(
                $self->conf->get( qw( config_app root_dir ) ) .
                    '/config/brackets/' . $bracket->{template} . '.yaml'
            );

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
    my $js_basepath = $self->conf->get( qw( config_app root_dir ) ) . '/static/js';

    for my $bracket ( $build_settings->{brackets}->@* ) {
        for my $quiz ( map { $_->{rooms}->@* } $bracket->{sets}->@* ) {
            my $material = $quiz->{material} || $bracket->{material} || $build_settings->{per_quiz}{material};

            $material_json_bibles->{ $material->{json_file}->to_string } //= do {
                my $bibles = decode_json( $material->{json_file}->slurp )->{bibles};
                [ grep { $bibles->{$_}{type} eq 'primary' } keys %$bibles ];
            };

            my $importmap =
                $quiz->{importmap} || $bracket->{importmap} || $build_settings->{per_quiz}{importmap};

            my $importmap_yaml = Dump($importmap);

            $importmap_js->{$importmap_yaml} //= Omniframe::Class::Javascript->new(
                basepath  => $js_basepath,
                importmap => $importmap,
            );

            $quiz->{distribution} = $importmap_js->{$importmap_yaml}->run(
                $js_basepath . '/modules/build_distribution.js',
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
    delete $build_settings->{per_quiz}{material}{json_file} if ( $build_settings->{per_quiz}{material} );

    for my $bracket ( $build_settings->{brackets}->@* ) {
        delete $bracket->{quizzes_per_team};
        delete $bracket->{rooms};
        delete $bracket->{teams};
        delete $bracket->{template};
        delete $bracket->{type};
        delete $bracket->{quizzes};
        delete $bracket->{material}{json_file} if ( $bracket->{material} );
        for ( map { $_->{rooms}->@* } $bracket->{sets}->@* ) {
            delete $_->{material}{json_file} if ( $_->{material} );
        }
    }

    return;
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

=head2 validate, freeze, thaw

=head2 build

=head1 WITH ROLE

L<Omniframe::Role::Bcrypt>, L<Omniframe::Role::Model>, L<Omniframe::Role::Time>.
