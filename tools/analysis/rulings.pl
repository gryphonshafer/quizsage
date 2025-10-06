#!/usr/bin/env perl
use exact -cli, -conf;
use QuizSage::Model::Label;
use QuizSage::Model::Meet;
use QuizSage::Model::Quiz;
use QuizSage::Model::Season;

my $label = QuizSage::Model::Label->new;

my $verse_to_list;
for my $alias ( grep { $_->{public} } $label->aliases->@* ) {
    my ($club) = reverse split( /\s/, $alias->{name} );

    for my $reference (
        $label->bible_ref
            ->clear
            ->in(
                map { $_->{range} } (
                    $label->descriptionate( $label->parse( $alias->{label} )
                )[1]->{ranges}->@*
            )
            ->as_verses
            ->@*
    ) {
        $verse_to_list->{$reference} = $club if (
            not $verse_to_list->{$reference} or
            $verse_to_list->{$reference} > $club
        );
    }
}

my @columns = (
    'Season name',
    'Season location',
    'Meet name',
    'Meet location',
    'Quiz bracket',
    'Quiz name',

    'Query ID',
    'Query type',
    'Query bible',
    'Query reference',
    'Club list',

    'Ruling action',
    'Ruling score query',
    'Ruling score quizzer increment',
    'Ruling score quizzer sum',
    'Ruling score ceiling bonus',
    'Ruling score nth quizzer bonus',
    'Ruling score follow bonus',
    'Ruling score team bonus increment',
    'Ruling score team increment',
    'Ruling score team sum',

    'Team name',
    'Team timeouts remaining',
    'Team score position',
    'Team score points',

    'Quizzer name',
    'Quizzer bible',
    'Quizzer tags',

    'Quizzer score correct',
    'Quizzer score incorrect',
    'Quizzer score open book',
    'Quizzer score points',
    'Quizzer score team points',

    'Quiz/quizzer bible count',
);

say csv(@columns);

for my $season ( QuizSage::Model::Season->new->every({ location => 'PNW Quizzing', hidden => 0 })->@* ) {
    for my $meet ( QuizSage::Model::Meet->new->every({ season_id => $season->id, hidden => 0 })->@* ) {
        for my $quiz ( QuizSage::Model::Quiz->new->every({ meet_id => $meet->id })->@* ) {
            for my $ruling (
                grep {
                    $_->{action} and (
                        $_->{action} eq 'correct'   or
                        $_->{action} eq 'incorrect' or
                        $_->{action} eq 'no_trigger'
                    )
                }
                $quiz->data->{state}{board}->@*
            ) {
                my ( $team, $quizzer );

                if ( $ruling->{action} eq 'no_trigger' ) {
                    $ruling->{action} = 'No trigger';
                }
                else {
                    $ruling->{action} = ucfirst $ruling->{action};

                    ($team)    = grep { $_->{id} eq $ruling->{team_id}    } $quiz->data->{state}{teams}->@*;
                    ($quizzer) = grep { $_->{id} eq $ruling->{quizzer_id} } $team->{quizzers}->@*;
                }

                my $quizzer_bibles = {};
                $quizzer_bibles->{ $_->{bible} }++
                    for ( map { $_->{quizzers}->@* } $quiz->data->{state}{teams}->@* );

                my $reference =
                    $ruling->{query}{book} . ' ' .
                    $ruling->{query}{chapter} . ':' .
                    $ruling->{query}{verse};

                row({
                    'Season name'     => $season->data->{name},
                    'Season location' => $season->data->{location},
                    'Meet name'       => $meet->data->{name},
                    'Meet location'   => $meet->data->{location},
                    'Quiz bracket'    => $quiz->data->{bracket},
                    'Quiz name'       => $quiz->data->{name},

                    'Query ID'        => $ruling->{id},
                    'Query type'      => $ruling->{type},
                    'Query bible'     => $ruling->{query}{bible},
                    'Query reference' => $reference,
                    'Club list'       => $verse_to_list->{$reference} // 'Full',

                    'Ruling action'                     => $ruling->{action},
                    'Ruling score query'                => $ruling->{score}{query},
                    'Ruling score quizzer increment'    => $ruling->{score}{quizzer_increment},
                    'Ruling score quizzer sum'          => $ruling->{score}{quizzer_sum},
                    'Ruling score ceiling bonus'        => $ruling->{score}{ceiling_bonus},
                    'Ruling score nth quizzer bonus'    => $ruling->{score}{nth_quizzer_bonus},
                    'Ruling score follow bonus'         => $ruling->{score}{follow_bonus},
                    'Ruling score team bonus increment' => $ruling->{score}{team_bonus_increment},
                    'Ruling score team increment'       => $ruling->{score}{team_increment},
                    'Ruling score team sum'             => $ruling->{score}{team_sum},

                    'Team name'               => ( ($team) ? $team->{name} : '' ),
                    'Team timeouts remaining' => ( ($team) ? $team->{timeouts_remaining} : '' ),
                    'Team score position'     => ( ($team) ? $team->{score}{position} : '' ),
                    'Team score points'       => ( ($team) ? $team->{score}{points} : '' ),

                    'Quizzer name'  => ( ($quizzer) ? $quizzer->{name} : '' ),
                    'Quizzer bible' => ( ($quizzer) ? $quizzer->{bible} : '' ),
                    'Quizzer tags'  => ( ($quizzer) ? join( ', ', sort +( $quizzer->{tags} // [] )->@* ) : '' ),

                    'Quizzer score correct'
                        => ( $quizzer and $quizzer->{score} ) ? $quizzer->{score}{correct} : '',
                    'Quizzer score incorrect'
                        => ( $quizzer and $quizzer->{score} ) ? $quizzer->{score}{incorrect} : '',
                    'Quizzer score open book'
                        => ( $quizzer and $quizzer->{score} ) ? $quizzer->{score}{open_book} : '',
                    'Quizzer score points'
                        => ( $quizzer and $quizzer->{score} ) ? $quizzer->{score}{points} : '',
                    'Quizzer score team points'
                        => ( $quizzer and $quizzer->{score} ) ? $quizzer->{score}{team_points} : '',

                    'Quiz/quizzer bible count'
                        => join( ', ',
                            map { $_ . ' (' . $quizzer_bibles->{$_} . ')' } sort keys %$quizzer_bibles
                        ),
                });
            }
        }
    }
}

sub row ($data) {
    say csv( map { $data->{$_} } @columns );
}

sub csv (@cells) {
    return join( ',', map {
        if ( not defined $_ ) {
            '',
        }
        elsif (/[,"]/) {
            s/"/""/g;
            '"' . $_ . '"';
        }
        else {
            $_;
        }
    } @cells );
}
