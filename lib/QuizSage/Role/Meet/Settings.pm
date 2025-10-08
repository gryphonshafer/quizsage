package QuizSage::Role::Meet::Settings;

use exact -role, -conf;
use Omniframe::Util::Data 'deepcopy';
use QuizSage::Model::Label;
use QuizSage::Model::Season;

with 'Omniframe::Role::Model';

sub merged_settings ($self) {
    my $meet_settings   = deepcopy( $self->data->{settings} // {} );
    my $season_settings = QuizSage::Model::Season->new
        ->load( $self->data->{season_id} )->data->{settings} // {};

    my $settings;

    ( $settings->{brackets} ) = grep { defined }
        delete $meet_settings->{brackets},
        delete $season_settings->{brackets},
        [];

    for my $source ( $season_settings, $meet_settings ) {
        for ( keys %{ $source->{roster} } ) {
            $settings->{roster}{$_} = delete $source->{roster}{$_} if ( $source->{roster}{$_} );
        }
        delete $source->{roster};
        for my $name ( qw( schedule per_quiz material ) ) {
            $settings->{$name} = delete $source->{$name} if ( $source->{$name} );
        }
    }

    return $settings;
}

sub build_settings ($self) {
    my $settings = $self->merged_settings;

    my $default_bible = $settings->{roster}{default_bible} // conf->get( qw( quiz_defaults bible ) );
    my $tags          = $settings->{roster}{tags} // {};

    $settings->{roster} = $self->thaw_roster_data(
        $settings->{roster}{data},
        $default_bible,
        $tags,
    )->{roster} if ( $settings->{roster}{data} );

    if ( my $material = delete $settings->{material} ) {
        $_->{material} //= $material for ( $settings->{brackets}->@* );
    }

    return $settings, $default_bible, $tags;
}

sub canonical_settings ( $self, $user_id = undef ) {
    my ( $settings, $default_bible, $tags ) = $self->build_settings;

    $settings->{roster} = {
        data => $self->freeze_roster_data(
            $settings->{roster},
            $default_bible,
            $tags,
        ),
        maybe tags          => $self->data->{settings}{roster}{tags},
        maybe default_bible => (
            ( $default_bible ne conf->get( qw( quiz_defaults bible ) ) )
                ? $default_bible
                : undef
        ),
    };

    my $label = QuizSage::Model::Label->new( maybe user_id => $user_id );
    for ( $settings, $settings->{brackets}->@* ) {
        if ( $_->{material} ) {
            $_->{material} = $label->canonicalize( $_->{material} );
            die 'Failed to parse material label/description' unless $_->{material};
        }
    }

    my @all_labels = grep { $_->{material} } $settings, $settings->{brackets}->@*;
    my %unique_labels;
    $unique_labels{$_}++ for (@all_labels);
    if ( @all_labels != keys %unique_labels ) {
        # if no meet label, create a meet label of the most common backet label
        ( $settings->{material} ) =
            map { $_->[0] }
            sort { $b->[1] <=> $a->[1] }
            map { [ $_, $unique_labels{$_} ] }
            keys %unique_labels
            if ( not $settings->{material} );

        # remove any bracket label that's the same as the meet label
        for ( $settings->{brackets}->@* ) {
            delete $_->{material} if ( $_->{material} and $_->{material} eq $settings->{material} );
        }

        # if only 1 bracket is without a label, move meet label to the bracket
        my @no_material_brackets = grep { not $_->{material} } $settings->{brackets}->@*;
        $no_material_brackets[0]->{material} = delete $settings->{material} if ( @no_material_brackets == 1 );
    }

    return $settings;
}

sub thaw_roster_data (
    $self,
    $roster_data   = undef,
    $default_bible = undef,
    $tags          = undef,
) {
    unless ( $roster_data and $default_bible and $tags ) {
        my $settings = $self->merged_settings;

        $roster_data //= $settings->{roster}{data};
        return unless $roster_data;

        $default_bible //=
            $settings->{roster}{default_bible} //
            conf->get( qw( quiz_defaults bible ) );

        $tags //= $settings->{roster}{tags} // {};
    }

    my @bible_acronyms = $self->dq('material')->get(
        'bible',
        ['acronym'],
        undef,
        { order_by => [ { -desc => { -length => 'acronym' } }, 'acronym' ] },
    )->run->column;

    my $bibles_re = '\b(?:' . join( '|', @bible_acronyms ) . ')\b';

    $tags->{$_} = ( ref $tags->{$_} ) ? $tags->{$_} : [ $tags->{$_} ] for ( qw( append default ) );

    my $parse_out_bibles_and_tags = sub ($text_ref) {
        $$text_ref =~ s/\s+/ /g;

        my $bible;
        if (@bible_acronyms) {
            $bible //= $1 while ( $$text_ref =~ s/($bibles_re)//i );
        }

        my @tags;
        push( @tags, sort split( /\s*[,;]+\s*/, $1 ) ) while ( $$text_ref =~ s/\(([^\)]*)\)//i );

        $$text_ref =~ s/\s+/ /g;
        $$text_ref =~ s/^\s|\s$//g;

        return $bible, (@tags) ? \@tags : undef;
    };

    return {
        default_bible => $default_bible,
        tags          => $tags,
        roster        => [
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
            } split( /\n\s*\n/, $roster_data )
        ],
    };
}

sub freeze_roster_data (
    $self,
    $roster        = undef,
    $default_bible = undef,
    $tags          = undef,
) {
    unless ( $roster and $default_bible and $tags ) {
        my $thawed_roster_data = $self->thaw_roster_data( $default_bible, $tags );

        $roster        = $thawed_roster_data->{roster};
        $default_bible = $thawed_roster_data->{default_bible};
        $tags          = $thawed_roster_data->{tags};
    }

    for my $quizzer ( map { $_->{quizzers}->@* } @$roster ) {
        delete $quizzer->{bible} if ( $quizzer->{bible} eq $default_bible );

        # remove any quizzer's tags that are append tags
        @{ $quizzer->{tags} } = sort grep {
            my $tag = $_;
            not grep { $tag eq $_ } $tags->{append}->@*;
        } $quizzer->{tags}->@*;

        # remove all quizzer's tags if the set matches the tag default set
        delete $quizzer->{tags}
            if ( join( ', ', $quizzer->{tags}->@* ) eq join( ', ', $tags->{default}->@* ) );
    }

    my $format_line = sub ( $obj = undef ) {
        return join( ' ',
            grep { defined }
            $obj->{name},
            $obj->{bible},
            ( $obj->{tags} and $obj->{tags}->@* )
                ? '(' . join( ', ', sort $obj->{tags}->@* ) . ')'
                : undef
        );
    };

    return join( "\n\n",
        map {
            my $team = $_;
            my $counts;

            for my $quizzer ( $team->{quizzers}->@* ) {
                $counts->{bible}{ $quizzer->{bible} }++ if ( $quizzer->{bible} );
                $counts->{tags}{$_}++ for ( $quizzer->{tags}->@* );
            }

            for my $bible ( keys $counts->{bible}->%* ) {
                next unless ( $team->{quizzers}->@* == $counts->{bible}{$bible} );
                delete $_->{bible} for ( $team->{quizzers}->@* );
                $team->{bible} = $bible;
            }

            for my $tag ( keys $counts->{tags}->%* ) {
                next unless ( $team->{quizzers}->@* == ( $counts->{tags}{$tag} // 0 ) );
                $_->{tags} = [ grep { $_ ne $tag } $_->{tags}->@* ] for ( $team->{quizzers}->@* );
                push( @{ $team->{tags} }, $tag );
            }

            join( "\n",
                $format_line->($team),
                map { $format_line->($_) } $team->{quizzers}->@*
            );
        } @$roster
    );
}

1;

=head1 NAME

QuizSage::Role::Meet::Settings

=head1 SYNOPSIS

    package Example::Settings;

    use exact -class;

    with 'QuizSage::Role::Meet::Settings';

    sub method ($self) {
        my $merged_settings                     = $self->merged_settings;
        my ( $settings, $default_bible, $tags ) = $self->build_settings;
        my $canonical_settings                  = $self->canonical_settings;

        my $hashref_of_roster_bible_and_tags = $self->thaw_roster_data(
            'roster_data',  # optional: text block of roster data
            $default_bible, # optional: default Bible translation acronym
            $tags,          # optional: hashref of "default" and/or "append" tags
        );

        my $roster = $hashref_of_roster_bible_and_tags->{roster};

        my $roster_data = $self->freeze_roster_data(
            $roster,        # optional: arrayref of hashrefs of roster data
            $default_bible, # optional: default Bible translation acronym
            $tags,          # optional: hashref of "default" and/or "append" tags
        );
    }

=head1 DESCRIPTION

This role provides some meet settings methods.

=head1 METHODS

=head2 merged_settings

Returns a hashref of merged settings for the meet, using season settings data
and then overriding with meets settings data. Also includes some node cleanup.

    my $merged_settings = $self->merged_settings;

=head2 build_settings

Gets data from C<merged_settings>, then thaws roster data via
C<thaw_roster_data>. It returns a settings data structure, default Bible
translation acronym, and a tags data structure.

    my ( $settings, $default_bible, $tags ) = $self->build_settings;

=head2 canonical_settings

Gets data from C<build_settings>, then canonicalizes C<roster.data> via
C<freeze_roster_data>. It also canonicalizes material labels.

    my $canonical_settings = $self->canonical_settings;

The method can optionally be provided with a user ID to inform label
canonicalization.

    my $canonical_settings = $self->canonical_settings($user_id);

=head2 thaw_roster_data

This method optinally takes roster data (as a text block), a default Bible
translation acronym, and a tags data structure (and if any of these are not
provided, the method sources them from C<merged_settings>). It then "thaws" the
roster data text block into a roster data structure.

    my $hashref_of_roster_bible_and_tags = $self->thaw_roster_data(
        'roster_data',  # optional: text block of roster data
        $default_bible, # optional: default Bible translation acronym
        $tags,          # optional: hashref of "default" and/or "append" tags
    );

=head2 freeze_roster_data

This method optionally takes a roster data structure, default Bible, and tags
hashref and returns a roster data text block.

    my $roster_data = $self->freeze_roster_data(
        $roster,        # optional: arrayref of hashrefs of roster data
        $default_bible, # optional: default Bible translation acronym
        $tags,          # optional: hashref of "default" and/or "append" tags
    );

=head1 DATA STRUCTURES

=head2 Roster Data Text

The roster data text block is a single string with line breaks between teams,
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

=head2 Roster Data Structure

THe roster data structure will follow the the following structure:

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

=head2 Tags

The tags hashref may have keys of C<default> (to represent any default tags
to apply to all quizzers) and/or C<append> (to contain any tags to append to all
quizzers). For example:

    ---
    default:
      - Veteran
    append:
      - Youth

=head1 WITH ROLE

L<Omniframe::Role::Model>.
