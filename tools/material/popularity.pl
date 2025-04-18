#!/usr/bin/env perl
use exact -conf, -cli;
use Bible::Reference;
use Mojo::UserAgent;
use Omniframe;
use QuizSage::Util::Material 'text2words';

my $opt = options( qw{ bible|b=s corpus|c=i sleep|s=i reference|r=s } );
$opt->{bible}  //= 'NIV';
$opt->{corpus} //= 26;
$opt->{sleep}  //= 1;

my $dq = Omniframe->with_roles('+Database')->new->dq('material');
my $ua = Mojo::UserAgent->new;

my $book_ids = { map { @$_ } $dq->sql('SELECT name, book_id FROM book')->run->all->@* };
my $refs     = ( not $opt->{reference} )
    ? $dq->sql(q{
        SELECT
            book.book_id,
            book.name AS book,
            verse.chapter,
            verse.verse
        FROM verse
        JOIN bible USING (bible_id)
        JOIN book USING (book_id)
        LEFT JOIN popularity ON
            book.book_id  = popularity.book_id AND
            verse.chapter = popularity.chapter AND
            verse.verse   = popularity.verse
        WHERE
            bible.acronym = ? AND
            popularity.popularity_id IS NULL
    })->run( $opt->{bible} )->all({})
    : [
        grep {
            not $dq->sql(q{
                SELECT COUNT(*) FROM popularity
                WHERE book_id = ? AND chapter = ? AND verse = ?
            })->run(
                $book_ids->{ $_->{book} },
                @$_{ qw( chapter verse ) },
            )->value
        }
        map {
            /^(?<book>.+?)\s(?<chapter>\d+):(?<verse>\d+)$/;
            +{%+};
        }
        Bible::Reference->new(
            acronyms   => 0,
            sorting    => 1,
            add_detail => 1,
        )->in( $opt->{reference} )->as_verses->@*
    ];

my ( $start_time, $processed ) = ( time, 0 );

for my $ref (@$refs) {
    sleep $opt->{sleep} if ($processed);

    my $text = $dq->sql(q{
        SELECT verse.text
        FROM verse
        JOIN bible USING (bible_id)
        JOIN book USING (book_id)
        WHERE
            bible.acronym = ?
            AND book.name = ?
            AND verse.chapter = ?
            AND verse.verse = ?
    })->run( $opt->{bible}, @$ref{ qw( book chapter verse ) } )->value;

    my $data = $ua
        ->get( 'https://books.google.com/ngrams/json', form => {
            corpus           => $opt->{corpus},
            smoothing        => 0,
            case_insensitive => 'true',
            content          => join( ',',
                map {
                    my $words = [ map { s/'.*//r } text2words($_)->@* ];
                    ( @$words >= 5 )
                        ? ( map { join( ' ', @$words[ $_ .. $_ + 4 ] ) } ( 0 .. @$words - 5 ) )
                        : join( ' ', @$words );
                }
                map { s/(?:^\s+|\s+$)//r }
                split( /[.?!]/, $text )
            ),
        } )
        ->result->json;

    my $score = 0;
    if (@$data) {
        $score += $_ * 1_000_000_000 for ( map { $_->{timeseries}->@* } @$data );
        $score /= @$data;
    }

    $dq->sql(q{
        INSERT INTO
            popularity ( book_id, chapter, verse, popularity )
            VALUES ( ?, ?, ?, ? )
    })->run(
        $book_ids->{ $ref->{book} },
        @$ref{ qw( chapter verse ) },
        $score,
    );

    printf "%5d/%-5d %7.3f%% %5.1f | %16s %-6s | %10.3f | %s\n",
        ++$processed,
        scalar(@$refs),
        $processed / @$refs * 100,
        ( time - $start_time ) / $processed * ( @$refs - $processed ) / 60 / 60,
        $ref->{book},
        $ref->{chapter} . ':' . $ref->{verse},
        $score,
        ( length $text > 40 ) ? substr( $text, 0, 40 ) . '...' : $text;
}

=head1 NAME

popularity.pl - Get and store verse popularity weights into a material database

=head1 SYNOPSIS

    popularity.pl OPTIONS
        -b, --bible     ACRONYMS    # default: NIV
        -c, --corpus    IDENTIFIER  # default: 26
        -s, --sleep     SECONDS     # default: 1
        -r, --reference REFERENCE
        -h, --help
        -m, --man

=head1 DESCRIPTION

This program will get and store verse popularity weights into a material
database. It does this using Google's Ngrams timeseries data, compiled into a
single index across the entire corpus' years.

=head2 -b, --bible

The Bible translation acronym for verse content to use for Ngram lookups.
Defaults to NIV.

=head2 -c, --corpus

The Google Ngrams corpus to use. Defaults to 26.

=head2 -s, --sleep

Integer of number of seconds to sleep between Ngram lookups. Defaults to 1.

=head2 -r, --reference

Normally, this program will process all verses for the given translation.
However, if you want to only process verses from a particular reference, you can
provide it.
