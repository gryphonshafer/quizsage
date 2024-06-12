package QuizSage::Model::Season;

use exact -class;
use Mojo::JSON qw( encode_json decode_json );
use QuizSage::Model::Meet;

with qw( Omniframe::Role::Model Omniframe::Role::Time QuizSage::Role::Data );

before 'create' => sub ( $self, $params ) {
    $params->{settings} //= $self->dataload('config/meets/defaults/season.yaml');
};

sub freeze ( $self, $data ) {
    $data->{start} = $self->time->parse( $data->{start} )->format('sqlite_min')
        if ( $self->is_dirty( 'start', $data ) );

    $data->{settings} = encode_json( $data->{settings} );
    undef $data->{settings} if ( $data->{settings} eq '{}' or $data->{settings} eq 'null' );

    return $data;
}

sub thaw ( $self, $data ) {
    $data->{settings} = ( defined $data->{settings} ) ? decode_json( $data->{settings} ) : {};
    return $data;
}

sub active_seasons ($self) {
    return [
        map {
            $_->{meets} = [
                map {
                    $_->{start} = $self->time
                        ->parse( $_->{start} )
                        ->format('%a, %b %e, %Y at %l:%M %p %Z');
                    $_;
                }
                $self->dq->get(
                    'meet',
                    [
                        qw( meet_id name location ),
                        [ \q{ STRFTIME( '%s', start ) } => 'start' ],
                    ],
                    { $self->id_name => $_->{season_id} },
                    { order_by => 'start' },
                )->run->all({})->@*
            ];
            $_;
        } $self->dq->get(
            $self->name,
            [ qw( season_id name location ) ],
            \q{
                STRFTIME( '%s', 'NOW' )
                    BETWEEN
                        STRFTIME( '%s', start )
                    AND
                        STRFTIME( '%s', start, days || ' days' )
            },
            { order_by => [ 'location', 'name' ] },
        )->run->all({})->@*
    ];
}

sub stats ($self) {
    my $meets = QuizSage::Model::Meet->new->every({ season_id => $self->id });
    my $rules = $self->deepcopy( $self->data->{settings}{statistics} ) // [ map { +{
        name   => $_->data->{name},
        weight => 1,
    } } @$meets ];

    my $stats = {
        meets => [
            sort {
                $a->{start} cmp $b->{start}
            }
            map {
                my $meet = $_;
                +{ map { $_ => $meet->data->{$_} } qw( meet_id name location start days ) };
            } @$meets
        ],
    };

    my $quizzers_meet_data;
    for my $meet (@$meets) {
        my $meet_stats = $meet->stats;
        for my $quizzer ( $meet_stats->{quizzers}->@* ) {
            $quizzers_meet_data->{ $quizzer->{name} }{ $meet->data->{name} } = {
                map { $_ => $quizzer->{$_} } qw( points_avg points_sum vra_sum tags team_name )
            };
        }
    }

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
                    my ($meet_rule) = grep { $_->{name} eq $meet->{name} } @{ $rules->{meets} };
                    $meet_data->{weight} = ($meet_rule) ? $meet_rule->{weight} : 0;

                    my %tags = map { $_ => 1 } @$tags, @{ $meet_data->{tags} // [] };
                    $tags = [ sort keys %tags ];
                    $unique_tags{$_}++ for (@$tags);

                    $meet_data;
                }
                $stats->{meets}->@*
            ];

            if ( $rules->{drop} ) {
                if ( $rules->{drop}{type} eq 'lowest' ) {
                    my ($lowest) =
                        sort { ( $a->{points_avg} // 0 ) <=> ( $b->{points_avg} // 0 ) }
                        @$quizzer_meets[ map { $_ - 1 } $rules->{drop}{meets}->@* ];
                    delete $lowest->{weight} if ($lowest);
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
                meets   => $quizzer_meets,
                ytd_avg => $quizzer_stats->{total_avg} / $quizzer_stats->{total_weight},
                tags    => $tags,
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

    return $stats;
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

=head2 active_seasons

This method will return a data structure of the current active seasons as
defined by if now is between the season's database values for C<start> and
C<start> plus C<days> duration.

    my $active_seasons = $quiz->active_seasons;

The data structure will be:

    ---
    - season_id: 1
      name     : Season Name
      location : Season Location
      meets    :
        - meet_id : 1,
          name    : Meet Name
          location: Meet Location
          start   : Sat, Jan 13, 2024 at  8:00 AM PST

=head2 stats

This method returns a data structure containing season statistics.

    my $stats = $season->stats;

The statistics hashref returned will contain keys for at least but perhaps not
limited to: C<quizzers>, C<meets>.

=head1 WITH ROLES

L<Omniframe::Role::Model>, L<Omniframe::Role::Time>, L<QuizSage::Role::Data>.
