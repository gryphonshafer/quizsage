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
            ->in( map { $_->{range} } $label->parse( $alias->{label} )->{ranges}->@* )
            ->as_verses
            ->@*
    ) {
        $verse_to_list->{$reference} = $club if (
            not $verse_to_list->{$reference} or
            $verse_to_list->{$reference} > $club
        );
    }
}

my ( $corrects, $findings );
for my $season ( QuizSage::Model::Season->new->every({
    name     => 'Luke',
    location => 'PNW Quizzing',
    hidden   => 0,
})->@* ) {
    for my $meet (
        QuizSage::Model::Meet->new->every(
            { season_id => $season->id, hidden => 0 },
            { order_by => 'start' },
        )->@*
    ) {
        my $position      = 0;
        my $quizzer_stats = { map {
            $_->{name} => +{
                position => ++$position,
                %$_,
            };
        } $meet->data->{stats}{quizzers}->@* };

        my $every_quiz = QuizSage::Model::Quiz->new->every({ meet_id => $meet->id });

        for my $quiz (@$every_quiz) {
            for my $ruling ( grep { $_->{action} eq 'correct' } $quiz->data->{state}{board}->@* ) {
                my ($team)    = grep { $_->{id} eq $ruling->{team_id}    } $quiz->data->{state}{teams}->@*;
                my ($quizzer) = grep { $_->{id} eq $ruling->{quizzer_id} } $team->{quizzers}->@*;

                my $reference =
                    $ruling->{query}{book} . ' ' .
                    $ruling->{query}{chapter} . ':' .
                    $ruling->{query}{verse};

                $corrects->{$reference}{ $quizzer->{name} }++;
            }
        }

        for my $quiz (@$every_quiz) {
            my @quizzers = map { $_->{quizzers}->@* } $quiz->data->{state}{teams}->@*;

            my $quizzer_bibles = {};
            $quizzer_bibles->{ $_->{bible} }++ for (@quizzers);

            for my $ruling (
                grep {
                    $_->{action} eq 'no_trigger'
                    and $_->{type} !~ /Q/
                    # and not $quizzer_bibles->{ESV}
                } $quiz->data->{state}{board}->@*
            ) {
                my $reference =
                    $ruling->{query}{book} . ' ' .
                    $ruling->{query}{chapter} . ':' .
                    $ruling->{query}{verse};

                my @quizzers_who_know_verse =
                    map {
                        $_->{stats}        = $quizzer_stats->{ $_->{name} };
                        $_->{stats}{count} = scalar( keys %$quizzer_stats );
                        $_;
                    }
                    grep { $corrects->{$reference}{ $_->{name} } }
                    grep { $_->{score}{correct} + $_->{score}{open_book} < 4 }
                    @quizzers;

                push( @$findings, {
                    meet_name               => $meet->data->{name},
                    bracket_name            => $quiz->data->{bracket},
                    quiz_name               => $quiz->data->{name},
                    query_id                => $ruling->{id},
                    query_bible             => $ruling->{bible},
                    query_type              => $ruling->{type},
                    query_reference         => $reference,
                    teams                   => $quiz->data->{state}{teams},
                    quizzers_who_know_verse => \@quizzers_who_know_verse,
                    club_list               => ( $verse_to_list->{$reference} )
                        ? 'Club ' . $verse_to_list->{$reference}
                        : 'Full Material',
                } ) if (@quizzers_who_know_verse);
            }
        }
    }
}

say csv(
    'Meet name',
    'Bracket name',
    'Quiz name',
    'Query ID',
    'Query bible',
    'Query type',
    'Query reference',
    'Club list',
    'Teams in quiz',
    'Quizzers who know verse',
);

for (@$findings) {
    my $quizzer_team = { map {
        my $team = $_;
        map { $_->{name} => $team->{name} } $_->{quizzers}->@*;
    } $_->{teams}->@* };

    $_->{quizzers_who_know_verse} = join( '; ', map {
        join( ', ',
            $_->{bible},
            $_->{stats}{position} . ' of ' . $_->{stats}{count},
            int( $_->{stats}{position} / $_->{stats}{count} * 100 ) . '%',
            $quizzer_team->{ $_->{name} },
        )
    } $_->{quizzers_who_know_verse}->@* );

    $_->{teams} = join( ', ', map { $_->{name} } $_->{teams}->@* );

    say csv( @$_{ qw{
        meet_name
        bracket_name
        quiz_name
        query_id
        query_bible
        query_type
        query_reference
        club_list
        teams
        quizzers_who_know_verse
    } } );
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
