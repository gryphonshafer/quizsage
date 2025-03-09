#!/usr/bin/env perl
use exact -cli, -conf;
use QuizSage::Model::Meet;
use QuizSage::Model::Quiz;
use QuizSage::Model::Season;

say csv(
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

    'Quizzer translations',
);

for my $season ( QuizSage::Model::Season->new->every({ hidden => 0 })->@* ) {
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

                say csv(
                    $season->data->{name},
                    $season->data->{location},

                    $meet->data->{name},
                    $meet->data->{location},

                    $quiz->data->{bracket},
                    $quiz->data->{name},

                    $ruling->{id},
                    $ruling->{type},
                    $ruling->{query}{bible},
                    join( ' ', $ruling->{query}{book}, $ruling->{query}{chapter}, $ruling->{query}{verse} ),
                    $ruling->{action},

                    $ruling->{score}{query},
                    $ruling->{score}{quizzer_increment},
                    $ruling->{score}{quizzer_sum},
                    $ruling->{score}{ceiling_bonus},
                    $ruling->{score}{nth_quizzer_bonus},
                    $ruling->{score}{follow_bonus},
                    $ruling->{score}{team_bonus_increment},
                    $ruling->{score}{team_increment},
                    $ruling->{score}{team_sum},

                    ($team) ? (
                        $team->{name},
                        $team->{timeouts_remaining},
                        $team->{score}{position},
                        $team->{score}{points},
                    ) : ( '' x 4 ),

                    ($quizzer) ? (
                        $quizzer->{name},
                        $quizzer->{bible},
                        join( ', ', sort +( $quizzer->{tags} // [] )->@* ),
                    ) : ( '' x 3 ),

                    ( $quizzer->{score} ) ? (
                        $quizzer->{score}{correct},
                        $quizzer->{score}{incorrect},
                        $quizzer->{score}{open_book},
                        $quizzer->{score}{points},
                        $quizzer->{score}{team_points},
                    ) : ( '' x 5 ),

                    join( ', ',
                        map { $_ . ' (' . $quizzer_bibles->{$_} . ')' } sort keys %$quizzer_bibles
                    ),
                );
            }
        }
    }
}

sub csv {
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
    } @_ );
}
