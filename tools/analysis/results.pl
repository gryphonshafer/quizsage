#!/usr/bin/env perl
use exact -cli, -conf;
use QuizSage::Model::Meet;
use QuizSage::Model::Quiz;
use QuizSage::Model::Season;

my $results;
for my $season ( QuizSage::Model::Season->new->every({ location => 'PNW Quizzing', hidden => 0 })->@* ) {
    for my $meet ( QuizSage::Model::Meet->new->every({ season_id => $season->id, hidden => 0 })->@* ) {
        for my $quiz ( QuizSage::Model::Quiz->new->every({ meet_id => $meet->id })->@* ) {
            for my $ruling ( $quiz->data->{state}{board}->@* ) {
                if ( $ruling->{action} eq 'correct' or $ruling->{action} eq 'incorrect' ) {
                    next unless ( $ruling->{qsstypes} );
                    my $type =
                        ( $ruling->{qsstypes} =~ /O/ ) ? 'open_book'  :
                        ( $ruling->{qsstypes} =~ /S/ ) ? 'synonymous' :
                        ( $ruling->{qsstypes} =~ /V/ ) ? 'verbatim'   : undef;
                    next unless ($type);
                    $results->{ $ruling->{action} }{$type}++;
                }
            }
        }
    }
}

print "| Result    | Open Book | Synonymous | Verbatim |\n";
print "|-----------|----------:|-----------:|---------:|\n";
my $totals;
for my $result ( sort keys %$results ) {
    printf "| %-9s | %9s | %10s | %8s |\n",
        ucfirst($result),
        map {
            $totals->{$_} += $results->{$result}{$_};
            $results->{$result}{$_};
        } qw( open_book synonymous verbatim );
}
printf "| %-9s | %9s | %10s | %8s |\n",
    'Total',
    map { $totals->{$_} } qw( open_book synonymous verbatim );
printf "| %-9s |  %7.1f%% |   %7.1f%% | %7.1f%% |\n",
    '',
    map {
        int( $results->{correct}{$_} / $totals->{$_} * 1_000 ) / 10
    } qw( open_book synonymous verbatim );
