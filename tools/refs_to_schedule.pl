#!/usr/bin/env perl
use exact -cli, -conf;
use Bible::Reference;
use DateTime::Duration;
use Omniframe::Class::Time;

my $opt = options( qw{
    range|r=s
    season_start|s=s
    meet_every|e=s
    meets_number|n=i
} );

$opt->{season_start} //= conf->get('season_start');
$opt->{meet_every}   //= '1 month, 2 weeks';
$opt->{meets_number} //= 5;

my $b_ref  = Bible::Reference->new;
my $chunks = [
    grep { $_->{size} }
    ( ( $opt->{range} // '' ) =~ /\|/ )
        ? (
            map {
                +{
                    refs => $b_ref->clear->add_detail(0)->in($_)->refs,
                    size => scalar( $b_ref->clear->add_detail(1)->in($_)->as_verses->@* ),
                };
            }
            split( /\|/, $opt->{range} )
        )
        : (
            map {
                s/^(?<book>.+)\s(?<chapter>\d+):1\-(?<verses>\d+)$//;
                +{
                    refs => $+{book} . ' ' . $+{chapter},
                    size => $+{verses},
                };
            }
            $b_ref->clear->add_detail(1)->in( $opt->{range} // '' )->as_chapters->@*
        )
];
pod2usage('Must provide a valid reference range') unless (@$chunks);

my $datetime = Omniframe::Class::Time->new->parse( $opt->{season_start} )->datetime;
pod2usage('Must use a valid season start') unless ($datetime);
$datetime->add( days => 1 ) while ( $datetime->day_of_week != 7 );

my $between_meets_duration;
$between_meets_duration->{ $+{unit} . 's' } += $+{amount}
    while ( $opt->{meet_every} =~ m/(?<amount>\d+)\s+(?<unit>year|month|week|day)s?/ig );
$between_meets_duration = DateTime::Duration->new(%$between_meets_duration);
pod2usage('Must use a valid duration') unless ($between_meets_duration);

my $chunks_per_meet = @$chunks / $opt->{meets_number};
my $chunks_used     = 0;
my $season_week     = 0;
my $sum_to_date     = 0;

say '| Week | Start       | End         | References                | Verses | Sum to Meet | Sum to Date |';
say '| ---: | ----------- | ----------- | ------------------------- | -----: | ----------: | ----------: |';

for my $meet_number ( 1 .. $opt->{meets_number} ) {
    my $chunks_to_use = int( $meet_number * $chunks_per_meet - $chunks_used + 0.5 );
    my @chunks_to_use = @$chunks[ $chunks_used .. $chunks_used + $chunks_to_use - 1 ];

    $chunks_used += $chunks_to_use;

    my $next_meet   = $datetime->clone->add($between_meets_duration);
    my $sum_to_meet = 0;

    while ( $next_meet->epoch > $datetime->epoch ) {
        printf "| %4d | %-10s | %-10s |",
            ++$season_week,
            $datetime->strftime('%a, %b %e'),
            $datetime->clone->add( days => 6 )->strftime('%a, %b %e');

        if ( my $chunk_to_use = shift @chunks_to_use ) {
            $sum_to_meet += $chunk_to_use->{size};
            $sum_to_date += $chunk_to_use->{size};

            printf " %-25s | %6d | %11d | %11d |\n",
                $chunk_to_use->{refs},
                $chunk_to_use->{size},
                $sum_to_meet,
                $sum_to_date;
        }
        else {
            printf " %-25s | %6s | %11s | %11s |\n",
                (
                    ( abs( $datetime->epoch - $next_meet->epoch ) <= 60 * 60 * 24 * 7 )
                        ? '**Meet ' . $meet_number . '**'
                        : '*Review*'
                ),
                ('') x 3;
        }

        $datetime->add( weeks => 1 );
    }
}

=head1 NAME

refs_to_schedule.pl - Convert a references string into a rough season schedule

=head1 SYNOPSIS

    refs_to_schedule.pl OPTIONS
        -r, --range        REFERENCES
        -s, --season_start DATE        # default: configuration's "season_start"
        -e, --meet_every   DURATION    # default: "1 month, 2 weeks"
        -n, --meets_number INTEGER     # default: 5
        -h, --help
        -m, --man

=head1 DESCRIPTION

This program will convert a references string into a rough season schedule.

=head2 -r, --range

Either a reference range that can be parsed by L<Bible::Reference>, or a set of
such ranges (separated by C<|> characters). If a single range, it'll be assumed
that it should be chunked into chapters, with a chunk used per study week. If
a set of ranges, then each item of the set will be assumed to be a chunk.

=head2 -s, --season_start

A date/time that can be parsed by L<Omniframe::Class::Time>. By default, it's
set by the configuration's C<season_start> value.

=head2 -e, --meet_every

Must be a string containing integers followed by duration unit names, plural or
singular. (i.e. year, month, week, day)

=head2 -n, --meets_number

The number of meets for the season. Defaults to 5.
