package QuizSage::Role::Meet::Editing;

use exact -role;
use Mojo::JSON 'decode_json';
use QuizSage::Model::Label;
use QuizSage::Model::Quiz;
use YAML::XS qw( Dump Load );

with qw(
    Omniframe::Role::Model
    QuizSage::Role::Meet::Build
    QuizSage::Role::Meet::Settings
);

sub save_after_edit ( $self, $user_id = undef ) {
    $self->data->{settings} = $self->canonical_settings($user_id);

    my $meet_quizzes = QuizSage::Model::Quiz->new->every({ meet_id => $self->id });
    my $meet_data    = $self->thaw( $self->freeze( $self->data ) );
    my $label        = QuizSage::Model::Label->new( maybe user_id => $user_id );

    my $get_settings = sub {
        my $settings = decode_json $self->saved_data->{settings};
        for ( $settings, $settings->{brackets}->@* ) {
            $_->{material} = $label->canonicalize( $_->{material} ) if ( $_->{material} );
        }

        return {
            new => $self->data->{settings},
            old => $settings,
        };
    };

    my $rosters;
    my $get_rosters = sub ( $settings = undef ) {
        $settings //= $get_settings->();
        return {
            map {
                $_ => $self->thaw_roster_data(
                    @{ $settings->{$_}{roster} }{ qw( data default_bible tags ) }
                )->{roster},
            } keys $settings->%*
        };
    };

    my @actions;

    if ( not @$meet_quizzes ) {
        push( @actions, 'reschedule_and_reevent', 'save' )
            if ( $self->is_dirty( 'start', $meet_data ) );

        if ( $self->is_dirty( 'settings', $meet_data ) ) {
            my $settings = $get_settings->();

            push( @actions, 'reschedule_and_reevent', 'save' ) if (
                Dump( $settings->{old}{schedule}  ) ne Dump( $settings->{new}{schedule}  ) or
                Dump( $settings->{old}{overrides} ) ne Dump( $settings->{new}{overrides} )
            );

            push( @actions, 'create_material_json', 'save' )
                if ( ( $settings->{old}{material} // '' ) ne ( $settings->{new}{material} // '' ) );

            if ( Dump( $settings->{old}{brackets} ) ne Dump( $settings->{new}{brackets} ) ) {
                my $old_brackets = Load( Dump( $settings->{old}{brackets} ) );
                my $new_brackets = Load( Dump( $settings->{new}{brackets} ) );
                for my $bracket ( $old_brackets->@*, $new_brackets->@* ) {
                    delete $bracket->{material};
                    delete $bracket->{weight};
                    delete $_->{weight} for ( $bracket->{quizzes}->@* );
                }

                if ( Dump($old_brackets) ne Dump($new_brackets) ) {
                    push( @actions, 'save', 'build' );
                }
                else {
                    $old_brackets = Load( Dump( $settings->{old}{brackets} ) );
                    $new_brackets = Load( Dump( $settings->{new}{brackets} ) );
                    for my $bracket ( $old_brackets->@*, $new_brackets->@* ) {
                        delete $bracket->{weight};
                        delete $_->{weight} for ( $bracket->{quizzes}->@* );
                    }
                    push( @actions, 'create_material_json', 'save' )
                        if ( Dump($old_brackets) eq Dump($new_brackets) );

                    $old_brackets = Load( Dump( $settings->{old}{brackets} ) );
                    $new_brackets = Load( Dump( $settings->{new}{brackets} ) );
                    delete $_->{material} for ( $old_brackets->@*, $new_brackets->@* );
                    push( @actions, 'null_saved_stats', 'save' )
                        if ( Dump($old_brackets) ne Dump($new_brackets) );
                }
            }

            $rosters = $get_rosters->($settings);
            if ( Dump( $rosters->{old} ) ne Dump( $rosters->{new} ) ) {
                if ( $rosters->{old}->@* != $rosters->{new}->@* ) {
                    push( @actions, 'save', 'build' );
                }
                else {
                    push( @actions, 'propagate_roster', 'save' );
                }
            }
        }
    }
    else {
        return 'Start cannot be changed after a meet has quizzes'
            if ( $self->is_dirty( 'start', $meet_data ) );

        if ( $self->is_dirty( 'settings', $meet_data ) ) {
            my $settings = $get_settings->();

            return 'Schedule and overrides cannot be changed after a meet has quizzes' if (
                Dump( $settings->{old}{schedule}  ) ne Dump( $settings->{new}{schedule}  ) or
                Dump( $settings->{old}{overrides} ) ne Dump( $settings->{new}{overrides} )
            );

            if ( Dump( $settings->{old}{brackets} ) ne Dump( $settings->{new}{brackets} ) ) {
                my $old_brackets = Load( Dump( $settings->{old}{brackets} ) );
                my $new_brackets = Load( Dump( $settings->{new}{brackets} ) );

                for my $bracket ( $old_brackets->@*, $new_brackets->@* ) {
                    delete $bracket->{weight};
                    delete $_->{weight} for ( $bracket->{quizzes}->@* );
                }

                if ( Dump($old_brackets) ne Dump($new_brackets) ) {
                    return 'Bracket settings (other than weights) cannot be changed after a meet has quizzes';
                }
                else {
                    push( @actions, 'null_saved_stats', 'save' );
                }
            }

            $rosters = $get_rosters->($settings);
            if ( Dump( $rosters->{old} ) ne Dump( $rosters->{new} ) ) {
                my $quizzers = { map { $_ => [
                    map { $_->{quizzers}->@* } $rosters->{$_}->@*
                ] } qw( old new ) };

                if (
                    $rosters->{old}->@* != $rosters->{new}->@* or
                    $quizzers->{old}->@* != $quizzers->{new}->@* or
                    join( ', ', map { $_->{bible} } $quizzers->{old}->@* ) ne
                    join( ', ', map { $_->{bible} } $quizzers->{new}->@* )
                ) {
                    return 'Team counts, quizzer counts, and quizzer bibles ' .
                        'cannot be changed after a meet has quizzes';
                }
                else {
                    push( @actions, 'null_saved_stats', 'save', 'propagate_roster' );
                }
            }
        }
    }

    push( @actions, 'save' )
        if ( grep { $self->is_dirty( $_, $meet_data ) } qw( name location days passwd ) );

    @actions = grep {
        $_ ne 'create_material_json' and
        $_ ne 'propagate_roster' and
        $_ ne 'reschedule_and_reevent'
    } @actions if ( grep { $_ eq 'build' } @actions );

    push( @actions, 'save' ) if (
        grep {
            $_ eq 'create_material_json' or
            $_ eq 'propagate_roster' or
            $_ eq 'reschedule_and_reevent'
        } @actions
    );

    my $warnings = [];

    if ( grep { $_ eq 'null_saved_stats' } @actions ) {
        $self->notice( 'Meet ' . $self->id . ' editing: null_saved_stats' );
        $self->data->{stats} = undef;
        $self->dq->sql('UPDATE season SET stats = NULL WHERE season_id = ?')->run( $self->data->{season_id} );
    }

    if ( grep { $_ eq 'create_material_json' } @actions ) {
        $self->notice( 'Meet ' . $self->id . ' editing: create_material_json' );
        $self->create_material_json( $self->data->{settings}, $user_id );
    }

    if ( grep { $_ eq 'propagate_roster' } @actions ) {
        $self->notice( 'Meet ' . $self->id . ' editing: propagate_roster' );
        $self->data->{build}{roster} = $rosters->{new};

        if (@$meet_quizzes) {
            my @team_map = map { +{
                old => $rosters->{old}->[$_],
                new => $rosters->{new}->[$_],
            } } 0 .. @{ $rosters->{old} } - 1;

            for my $quiz (@$meet_quizzes) {
                for my $i ( 0 .. @{ $quiz->data->{settings}{teams} } - 1 ) {
                    ( $quiz->data->{settings}{teams}[$i] ) = map { $_->{new} } grep {
                        $_->{old}{name} eq $quiz->data->{settings}{teams}[$i]{name}
                    } @team_map;

                    if ( $quiz->data->{state} ) {
                        my $settings_team = $quiz->data->{settings}{teams}[$i];
                        my $state_team    = $quiz->data->{state}{teams}[$i];

                        $state_team->{name} = $settings_team->{name};

                        for my $j ( 0 .. @{ $settings_team->{quizzers} } - 1 ) {
                            $state_team->{quizzers}[$j]{name}  = $settings_team->{quizzers}[$j]{name};
                            $state_team->{quizzers}[$j]{bible} = $settings_team->{quizzers}[$j]{bible};
                            $state_team->{quizzers}[$j]{tags}  = $settings_team->{quizzers}[$j]{tags}
                                if ( $settings_team->{quizzers}[$j]{tags} );
                        }
                    }
                }

                $quiz->save;
            }
        }
    }

    if ( grep { $_ eq 'reschedule_and_reevent' } @actions ) {
        $self->notice( 'Meet ' . $self->id . ' editing: reschedule_and_reevent' );

        my $build_settings = Load( Dump( $self->data->{build} ) );
        $build_settings->{schedule} = Load( Dump( $self->data->{settings}{schedule} // {} ) );
        $warnings = $self->schedule_integration($build_settings);

        $self->data->{build}{events} = $build_settings->{events};

        for my $b ( 0 .. @{ $build_settings->{brackets} } - 1 ) {
            for my $s ( 0 .. @{ $build_settings->{brackets}[$b]{sets} } - 1 ) {
                for my $r ( 0 .. @{ $build_settings->{brackets}[$b]{sets}[$s]{rooms} } - 1 ) {
                    for ( qw( start stop ) ) {
                        $self->data->{build}{brackets}[$b]{sets}[$s]{rooms}[$r]{$_} =
                            $build_settings->{brackets}[$b]{sets}[$s]{rooms}[$r]{$_}
                            if ( defined $build_settings->{brackets}[$b]{sets}[$s]{rooms}[$r]{$_} );
                    }
                }
            }
        }
    }

    if ( grep { $_ eq 'save' } @actions ) {
        $self->notice( 'Meet ' . $self->id . ' editing: save' );
        $self->save;
    }

    if ( grep { $_ eq 'build' } @actions ) {
        $self->notice( 'Meet ' . $self->id . ' editing: build' );
        $warnings = $self->build($user_id);
    }

    return 'success', $warnings // [];
}

1;

=head1 NAME

QuizSage::Role::Meet::Editing

=head1 SYNOPSIS

    package Package;

    use exact -class;

    with 'QuizSage::Role::Meet::Editing';

    sub method ( $self, $user_id = undef ) {
        my ( $result, $warnings ) = $self->save_after_edit($user_id);
    }

=head1 DESCRIPTION

This role provides meet editing capability.

=head2 save_after_edit

This method will look at C<data> that's changed (but not yet saved) in the object,
and based on what data has changed, potentially save it, and based on what data
was changed, potentially thereafter rebuild the meet's C<build>.

It'll return either "rebuilt" and an arrayref of any warnings from the build,
or it'll return a text message of any error as to why the save was rejected.

=head1 WITH ROLES

L<Omniframe::Role::Model>, L<QuizSage::Role::Meet::Build>,
L<QuizSage::Role::Meet::Settings>.
