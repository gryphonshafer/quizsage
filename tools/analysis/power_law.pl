#!/usr/bin/env perl
use exact -conf;
use QuizSage::Model::Season;
use QuizSage::Model::Meet;

my $power_law_exponent = 1.55;
my $model_runs         = 3;
my $max_points         = 31;
my $min_points         = 0;
my $boost_base         = 28;
my $boost_rate         = 3;

my @historic_points_per_quiz =
    map { $_->{points} }
    grep { $_->{bracket} eq 'Preliminary' }
    map { $_->{quizzes}->@* }
    map { $_->data->{stats}{quizzers}->@* }
    grep { $_->data->{stats} and $_->data->{stats}->%* }
    map { QuizSage::Model::Meet->new->every({ season_id => $_->id, hidden => 0 })->@* }
    QuizSage::Model::Season->new->every({ location => 'PNW Quizzing', hidden => 0 })->@*;

my $real_modes;
$real_modes->{$_}++ for @historic_points_per_quiz;
my $population = @historic_points_per_quiz;

sub model_modes ($power_law_exponent) {
    my @weights = map {
        my $weight = 1 / ( ( $_ + 1 ) ** $power_law_exponent );
        ( $_ >= $boost_base ) ? $weight * $boost_rate : $weight;
    } $min_points .. $max_points;

    my $sum_weights = 0;
    $sum_weights += $_ for @weights;

    my @cdf;
    my $cumulative = 0;
    for my $p ( map { $_ / $sum_weights } @weights ) {
        $cumulative += $p;
        push( @cdf, $cumulative );
    }

    my $model_modes;
    for ( 1 .. $population ) {
        my $rand   = rand();
        my $points = 0;
        for ( $min_points .. $max_points ) {
            if ( $rand <= $cdf[$_] ) {
                $points = $_;
                last;
            }
        }
        $model_modes->{$points}++;
    }

    return $model_modes;
}

say '| Points | Real | ' . join( ' | ', map { "Model $_" } ( 1 .. $model_runs ) ) . ' | Avg. | Delta |';
say '|-------:|-----:|' .  join( ':|', map { '-' x 8 } ( 1 .. $model_runs ) ) . ':|-----:|------:|';

my $model;
$model->{$_} = model_modes($power_law_exponent) for ( 1 .. $model_runs );

my ( $sums, @delta );
my $format = '| %6s | %4s | ' . join( ' | ', map { '%7s' } ( 1 .. $model_runs ) ) . ' | %4s | %5s |' . "\n";
for my $points ( reverse $min_points .. $max_points ) {
    my @model_runs_data = map { $model->{$_}{$points} // 0 } ( 1 .. $model_runs );
    my $model_runs_data_sum = 0;
    $model_runs_data_sum += $_ for @model_runs_data;
    push( @delta, int( ( $real_modes->{$points} // 0 ) - ( $model_runs_data_sum / @model_runs_data ) ) );

    printf $format,
        $points,
        $real_modes->{$points} // 0,
        @model_runs_data,
        int( $model_runs_data_sum / @model_runs_data ),
        $delta[-1];

    $sums->{real} += ( $real_modes->{$points} // 0 ) * $points;
    $sums->{ 'model_' . $_ } += ( $model->{$_}{$points} // 0 ) * $points for ( 1 .. $model_runs );
}

my $delta_sum = 0;
$delta_sum += abs($_) for @delta;

my @model_runs_data = map { $sums->{ 'model_' . $_ } } ( 1 .. $model_runs );
my $model_runs_data_sum = 0;
$model_runs_data_sum += $_ for @model_runs_data;

printf $format . "\n",
    '',
    $sums->{real},
    @model_runs_data,
    int( $model_runs_data_sum / @model_runs_data ),
    $delta_sum;
