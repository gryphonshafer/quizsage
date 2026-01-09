package QuizSage::Model::Season;

use exact -class, -conf;
use Mojo::JSON qw( to_json from_json );
use Omniframe::Class::Time;
use Omniframe::Util::Data qw( dataload deepcopy );
use QuizSage::Model::Meet;

with 'Omniframe::Role::Model';

class_has active => 1;

my $time = Omniframe::Class::Time->new;

before 'create' => sub ( $self, $params ) {
    $params->{settings} //= dataload('config/meets/defaults/season.yaml');
};

sub freeze ( $self, $data ) {
    $data->{start} = $time->parse( $data->{start} )->format('sqlite_min')
        if ( $self->is_dirty( 'start', $data ) );

    for ( qw( settings stats ) ) {
        $data->{$_} = to_json( $data->{$_} );
        undef $data->{$_} if ( $data->{$_} eq '{}' or $data->{$_} eq 'null' );
    }

    return $data;
}

sub thaw ( $self, $data ) {
    $data->{$_} = ( defined $data->{$_} ) ? from_json( $data->{$_} ) : {} for ( qw( settings stats ) );
    return $data;
}

sub seasons ($self) {
    return [
        map {
            $_->{meets} = [
                $self->dq->get(
                    'meet',
                    [ qw( meet_id name location start hidden ) ],
                    { $self->id_name => $_->{season_id} },
                    { order_by => 'start' },
                )->run->all({})->@*
            ] if ( $_->{active} );
            $_;
        } $self->dq->get(
            $self->name,
            [
                qw( season_id name location start hidden ),
                [ \q{ DATETIME( start, '+' || days || ' day' ) }, 'stop' ],
                [
                    \q{
                        CASE WHEN
                            STRFTIME( '%s', 'NOW' )
                                BETWEEN
                                    STRFTIME( '%s', start )
                                AND
                                    STRFTIME( '%s', start, days || ' days' )
                        THEN 1 ELSE 0 END
                    },
                    'active',
                ],
            ],
            { active => 1 },
            { order_by => [ { -desc => 'start' }, 'location', 'name' ] },
        )->run->all({})->@*
    ];
}

sub stats ( $self, $rebuild = 0 ) {
    my $meets = QuizSage::Model::Meet->new->every({ season_id => $self->id, hidden => 0 });
    my $rules = deepcopy( $self->data->{settings}{statistics} ) // { meets => [ map { +{
        name   => $_->data->{name},
        weight => 1,
    } } @$meets ] };

    my $get_meet_id = $self->dq->sql(q{
        SELECT meet.meet_id
        FROM meet
        JOIN season USING (season_id)
        WHERE
            season.active AND NOT season.hidden AND NOT meet.hidden AND
            season.name = ? AND season.location = ? AND meet.name = ?
    });
    my $remote_meets = [
        grep { defined }
        map {
            my $id = $get_meet_id->run(@$_)->value;
            ($id) ? QuizSage::Model::Meet->new->load($id) : undef;
        }
        map {
            my $meet = $_;
            if ( not ref $meet->{merge} ) {
                [
                    $self->data->{name},
                    $meet->{merge},
                    $meet->{name},
                ];
            }
            elsif ( ref $meet->{merge} eq 'HASH' ) {
                [
                    $meet->{merge}{season} // $self->data->{name},
                    $meet->{merge}{location},
                    $meet->{merge}{meet} // $meet->{name},
                ];
            }
            elsif ( ref $meet->{merge} eq 'ARRAY' ) {
                map {
                    ( ref $_ )
                        ? [
                            $_->{season} // $self->data->{name},
                            $_->{location},
                            $_->{meet} // $meet->{name},
                        ]
                        : [
                            $self->data->{name},
                            $_,
                            $meet->{name},
                        ];
                } $meet->{merge}->@*;
            }
        }
        grep { $_->{merge} }
        $rules->{meets}->@*
    ];

    my $rebuild_stats_if_before = $time->parse( conf->get('rebuild_stats_if_before') )->{datetime}->epoch;

    my @season_meets_last_mod = map { +{
        meet                => $_,
        last_modified_epoch => $time->parse( $_->data->{last_modified} )->{datetime}->epoch,
    } } @$meets, @$remote_meets;

    my $triggered_rebuild = 0;
    for ( grep { $_->{last_modified_epoch} < $rebuild_stats_if_before } @season_meets_last_mod ) {
        $_->{meet}->stats(1);
        $triggered_rebuild = 1;
    }

    if ( not $triggered_rebuild ) {
        my $this_last_mod = $time->parse( $self->data->{last_modified} )->{datetime}->epoch;
        $triggered_rebuild = 1
            if ( grep { $this_last_mod < $_->{last_modified_epoch} } @season_meets_last_mod );
    }

    return $self->data->{stats} unless (
        $rebuild or
        $triggered_rebuild or
        not $self->data->{stats}->%* or
        $time->parse( $self->data->{last_modified} )->{datetime}->epoch <
            $time->parse( conf->get('rebuild_stats_if_before') )->{datetime}->epoch
    );

    my $stats = {
        meet_count => scalar @$meets,
        meets      => [
            sort {
                $a->{start}    cmp $b->{start} or
                $a->{name}     cmp $b->{name}  or
                $a->{location} cmp $b->{location}
            }
            map {
                my $meet = $_;
                +{ map { $_ => $meet->data->{$_} } qw( meet_id name location start days ) };
            } @$meets, @$remote_meets
        ],
    };

    my $quizzers_meet_data;
    for my $meet ( @$meets, @$remote_meets ) {
        my $meet_stats = $meet->stats($rebuild);

        push( @{ $stats->{rookies_of_the_meets} }, +{
            rookie => $meet_stats->{meta}{rookie_of_the_meet},
            meet   => +{ map { $_ => $meet->data->{$_} } qw( meet_id name location start days ) },
        } ) if ( $meet_stats->{meta}{rookie_of_the_meet} );

        for my $quizzer ( $meet_stats->{quizzers}->@* ) {
            $quizzers_meet_data->{ $quizzer->{name} }{ $meet->data->{name} } = {
                map { $_ => $quizzer->{$_} } qw( points_avg points_sum vra_sum tags team_name )
            };
        }
    }

    $stats->{rookies_of_the_meets} = [
        sort {
            $a->{meet}{start}    cmp $b->{meet}{start} or
            $a->{meet}{name}     cmp $b->{meet}{name}  or
            $a->{meet}{location} cmp $b->{meet}{location}
        }
        $stats->{rookies_of_the_meets}->@*
    ];

    my %unique_tags;
    $stats->{quizzers} = [
        sort {
            $b->{ytd_avg} <=> $a->{ytd_avg} ||
            $a->{name} cmp $b->{name}
        }
        map {
            my $quizzer_name = $_;
            my $tags         = [];

            my $quizzer_meets = [
                map {
                    my $meet = $_;

                    my $meet_data = $quizzers_meet_data->{$quizzer_name}{ $meet->{name} };
                    my ($meet_rule) = grep { $_->{name} eq $meet->{name} } @{ $rules->{meets} // [] };
                    $meet_data->{weight} = ($meet_rule) ? $meet_rule->{weight} : 0;

                    my %tags = map { $_ => 1 } @$tags, @{ $meet_data->{tags} // [] };
                    $tags = [ sort keys %tags ];
                    $unique_tags{$_}++ for (@$tags);

                    $meet_data;
                }
                sort {
                    $a->{start}    cmp $b->{start} or
                    $a->{name}     cmp $b->{name}  or
                    $a->{location} cmp $b->{location}
                }
                map {
                    my $meet = $_;
                    +{ map { $_ => $meet->data->{$_} } qw( meet_id name location start days ) };
                }
                @$meets
            ];

            if ( $rules->{drop} ) {
                if ( $rules->{drop}{type} eq 'lowest' ) {
                    my ($lowest) =
                        sort { ( $a->{points_avg} // 0 ) <=> ( $b->{points_avg} // 0 ) }
                        @$quizzer_meets[ map { $_ - 1 } $rules->{drop}{meets}->@* ];
                    $lowest->{weight} = 0 if ($lowest);
                }
            }

            my $quizzer_stats = { map { $_ => 0 } qw( total_avg total_weight vra_sum total_points ) };
            for (@$quizzer_meets) {
                $quizzer_stats->{vra_sum}      += $_->{vra_sum}    // 0;
                $quizzer_stats->{total_points} += $_->{points_sum} // 0;

                if ( $_->{weight} ) {
                    $quizzer_stats->{total_weight} += $_->{weight};
                    $quizzer_stats->{total_avg}    += $_->{weight} * ( $_->{points_avg} // 0 );
                }
            };

            +{
                name    => $_,
                tags    => $tags,
                meets   => $quizzer_meets,
                ytd_avg => (
                    $quizzer_stats->{total_avg} / (
                        ( $quizzer_stats->{total_weight} )
                            ? $quizzer_stats->{total_weight}
                            : scalar(@$quizzer_meets)
                    )
                ),
                %$quizzer_stats,
            };
        }
        keys %$quizzers_meet_data
    ];
    $stats->{tags} = [ sort keys %unique_tags ];

    $stats->{vra_quizzers} = [
        sort { $b->{vra_sum} <=> $a->{vra_sum} }
        grep { $_->{vra_sum} }
        $stats->{quizzers}->@*
    ];

    $self->data->{stats}         = $stats;
    $self->data->{last_modified} = \q{ STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' ) },
    $self->save;
    $self->info( 'Season stats generated for: ' . $self->id );

    return $stats;
}

sub admin_auth ( $self, $user ) {
    return (
        ( $self->data->{user_id} // 0 ) == $user->id or
        $self->dq->sql(q{
            SELECT COUNT(*)
            FROM administrator
            WHERE season_id = ? AND user_id = ?
        })->run( $self->id, $user->id )->value
    ) ? 1 : 0;
}

sub admin ( $self, $action, $user_id ) {
    $self->dq->sql(
        ( $action eq 'add' )
            ? 'INSERT INTO administrator ( user_id, season_id ) VALUES ( ?, ? )'
            : 'DELETE FROM administrator WHERE user_id = ? AND season_id = ?'
    )->run( $user_id, $self->id );

    return $self;
}

sub admins ($self) {
    return $self->dq->sql(q{
        SELECT u.first_name, u.last_name, u.email, u.user_id
        FROM user AS u
        JOIN administrator AS a USING (user_id)
        WHERE a.season_id = ?
        ORDER BY 1, 2, 3
    })->run( $self->id )->all({});
}

1;

=head1 NAME

QuizSage::Model::Season

=head1 SYNOPSIS

    use QuizSage::Model::Season;

    my $quiz = QuizSage::Model::Season->new;
    my $active_seasons = $quiz->active_seasons;

=head1 DESCRIPTION

This class is the model for season objects.

=head1 EXTENDED METHOD

=head2 create

Extended from L<Omniframe::Role::Model>, this method will populate the
C<settings> value from C<config/meets/defaults/season.yaml> if that value isn't
explicitly provided.

=head1 OBJECT METHODS

=head2 freeze, thaw

Likely not used directly, these method run data pre-save to and post-read from
the database functions. C<freeze> will canonically format the C<start> datetime
and encode C<settings> C<thaw> will decode C<settings>.

=head2 seasons

This method will return a data structure of all seasons, with C<active> being
if the season is a current active season as defined by if now is between the
season's database values for C<start> and C<start> plus C<days> duration.

    my $seasons = $quiz->seasons;

=head2 stats

This method returns a data structure containing season statistics.

    my $stats = $season->stats;

The statistics hashref returned will contain keys for at least but perhaps not
limited to: C<quizzers>, C<meets>.

=head2 admin_auth

Requires a loaded user object and will return a boolean of whether the user is
authorized as an administrator of the season.

=head2 admin

Requires either "add" or "remove" followed by a user ID. Will then either add
or remove that user to/from the list of administrators of the season.

=head2 admins

Returns an arrayref of hashrefs of users who are administrators of the season.

=head1 WITH ROLE

L<Omniframe::Role::Model>.
