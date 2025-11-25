#!/usr/bin/env perl
use exact -cli, -conf;
use QuizSage::Model::Meet;
use QuizSage::Model::Quiz;

my $opt = options( qw{ id|i=i name|n=s write|w quizzes|q } );
pod2usage('Required input missing') unless ( $opt->{id} and $opt->{name} );

my $meet = QuizSage::Model::Meet->new->load( $opt->{id} );
my $team;
( $team->{settings}{current} ) =
    grep { /^$opt->{name}\n/ }
    split( '\n\n', $meet->data->{settings}{roster}{data} )
    if ( $meet->data->{settings} );
( $team->{build}{current} ) = grep { $_->{name} eq $opt->{name} } $meet->data->{build}{roster}->@*
    if ( $meet->data->{build} );
die "No team settings or team build found\n" unless ( $team->{settings}{current} or $team->{build}{current} );

if ( not $opt->{write} ) {
    say '.' x 40, 'SETTINGS', "\n", $team->{settings}{current} if ( $team->{settings}{current} );
    if ( $team->{build}{current} ) {
        say "\n", '.' x 40, 'BUILD';
        say $team->{build}{current}{name};
        for my $quizzer ( @{ $team->{build}{current}{quizzers} // [] } ) {
            say join( ' ',
                $quizzer->{name},
                grep { defined }
                    ( ( $quizzer->{bible} ) ? $quizzer->{bible} : undef ),
                    ( ( $quizzer->{tags}  ) ? '(' . join( ', ', $quizzer->{tags}->@* ) . ')' : undef ),
            );
        }
    }
}

else {
    for my $type ( grep { $team->{$_}{current} } qw( settings build ) ) {
        say "Enter text block for $type (excluding team name):";

        my $block;
        while ( my $line = <STDIN> ) {
            last if ( $line =~ /^\s*$/ );
            $block .= $line;
        }
        next unless $block;
        $block =~ s/(?:^\s+|\s+$)//mg;
        $block =~ s/[ \t]+/ /g;

        if ( $type eq 'settings' ) {
            $team->{$type}{new} = $opt->{name} . "\n" . $block;
        }
        elsif ( $type eq 'build' ) {
            $team->{$type}{new} = [ map {
                my $quizzer;
                $quizzer->{tags} = [ split( /\s*,\s*/, $1 ) ] if ( s/\s+\(([^\)]+)\)// );
                my @parts = split( /\s+/ );
                $quizzer->{bible} = pop @parts;
                $quizzer->{name}  = join( ' ', @parts );
                $quizzer;
            } split( /\n/, $block ) ];
        }
    }

    $meet->dq->begin_work;

    my $data   = $meet->data->{settings}{roster}{data};
    my $index  = index( $data, $team->{settings}{current} );
    my $length = length( $team->{settings}{current} );

    $meet->data->{settings}{roster}{data} = join( '',
        substr( $data, 0, $index ),
        $team->{settings}{new},
        substr( $data, $index + $length ),
    );

    my ( $current_count, $new_count ) = map { scalar @$_ }
        $team->{build}{current}{quizzers}, $team->{build}{new};

    $team->{build}{current}{quizzers} = $team->{build}{new};

    if ( $opt->{quizzes} ) {
        die "Unable to edit quizzes if quizzer counts change\n" if ( $current_count != $new_count );

        for my $quiz ( QuizSage::Model::Quiz->new->every({ meet_id => $opt->{id} })->@* ) {
            if ( $quiz->data->{settings} and $quiz->data->{settings}{teams} ) {
                my ($this_team) = grep { $_->{name} eq $opt->{name} } $quiz->data->{settings}{teams}->@*;
                $this_team->{quizzers} = $team->{build}{new} if ($this_team);
            }

            if ( $quiz->data->{state} and $quiz->data->{state}{teams} ) {
                my ($this_team) = grep { $_->{name} eq $opt->{name} } $quiz->data->{state}{teams}->@*;
                if ($this_team) {
                    for my $edit (
                        map {
                            +{
                                record => $this_team->{quizzers}[$_],
                                change => $team->{build}{new}[$_],
                            }
                        } 0 .. @{ $this_team->{quizzers} } - 1
                    ) {
                        $edit->{record}{name}  = $edit->{change}{name};
                        $edit->{record}{bible} = $edit->{change}{bible};
                        $edit->{record}{tags}  = $edit->{change}{tags};
                    }
                }
            }

            $quiz->save;
        }
    }

    $meet->save;
    $meet->dq->commit;
}

=head1 NAME

roster.pl - Edit meet roster data (including across quizzes)

=head1 SYNOPSIS

    roster.pl OPTIONS
        -i, --id      MEET_PRIMARY_KEY_ID # required
        -n, --name    TEAM_NAME           # required
        -w, --write                       # write changes from later input
        -q, --quizzes                     # include changes in quizzes
        -h, --help
        -m, --man

=head1 DESCRIPTION

This program will edit meet roster data (including across quizzes).

=head2 -i, --id

Meet primary key ID.

=head2 -n, --name

Team name.

=head2 -w, --write

Flat that if set will cause the program to ask for input, which will be parsed
and written to the database.

=head2 -q, --quizzes

Flag that if set will cause changes to happen across any created quizzes of the
meet, not just the meet settings and build data.

Note that you very likely don't want to do this during a meet.
