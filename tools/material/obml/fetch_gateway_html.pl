#!/usr/bin/env perl
use exact -cli;
use Bible::OBML::Gateway;
use File::Path 'make_path';
use Mojo::File 'path';
use Mojo::JSON qw( to_json from_json );

my $opt = options( qw{ dir|d=s status|s=s wait|w=i bible|b=s@ norandom|n } );

$opt->{dir}    ||= './gateway_html';
$opt->{status} ||= './local/fetch.gateway.status.json';
$opt->{wait}   //= 1;

$opt->{$_} = path( $opt->{$_} ) for ( qw( dir status ) );

my $bg = Bible::OBML::Gateway->new;

my $status;

unless ( -w $opt->{status} ) {
    make_path( $opt->{status}->dirname );

    $status = [
        map { +{ bible => $_ } } (
            ( $opt->{bible} )
                ? ( sort map { uc $_ } @{ $opt->{bible} } )
                : (
                    sort
                    map { $_->{acronym} }
                    map { @{ $_->{translations} } }
                    grep { $_->{acronym} eq 'EN' } @{ $bg->translations }
                )
        )
    ];

    $opt->{status}->spew( to_json($status), 'UTF-8' );
}
else {
    $status = from_json( $opt->{status}->slurp('UTF-8') );
}

for my $bible ( shuffle(@$status) ) {
    unless ( $bible->{books} ) {
        sleep $opt->{wait};
        say $bible->{bible};

        $bible->{books} = [
            map {
                ( my $book_name = $_->{display} ) =~ s/\s/_/g;
                +{
                    book_display => $_->{display},
                    book_name    => $book_name,
                    chapters     => [ map { $_->{chapter} } $_->{chapters}->@* ],
                };
            } @{ $bg->structure( $bible->{bible} ) }
        ];

        $opt->{status}->spew( to_json($status), 'UTF-8' );
    }
}

my @chapters = shuffle(
    grep { not -f $_->{file} }
    map {
        my $book = $_;
        map {
            +{
                %$book,
                chapter => $_,
                file    => $opt->{dir}->child(
                    $book->{bible} . '/' . $book->{book_name} . '/' .
                    $book->{bible} . '_' . $book->{book_name}  . '_' . $_ . '.html'
                ),
            };
        } @{ $book->{chapters} }
    }
    map {
        my $bible = $_;
        map { $_->{bible} = $bible->{bible}; $_ } @{ $bible->{books} };
    }
    @$status
);

if ( $opt->{bible} ) {
    my @bibles = map { uc $_ } @{ $opt->{bible} };

    @chapters = grep {
        my $bible = $_->{bible};
        grep { $_ eq $bible } @bibles;
    } @chapters;
}

my ( $start, $total ) = ( time, scalar(@chapters) );

for ( my $i = 0; $i < @chapters; $i++ ) {
    my $chapter = $chapters[$i];

    make_path( $chapter->{file}->dirname );
    sleep $opt->{wait};

    try {
        $chapter->{file}->spew(
            $bg->fetch(
                $chapter->{book_display}  . ' ' . $chapter->{chapter},
                $chapter->{bible},
            ),
            'UTF-8',
        );
    }
    catch ($e) {
        warn join( ' ',
            'Error attempting:',
            $chapter->{bible},
            $chapter->{book_display},
            $chapter->{chapter},
        ) . "\n";
        warn $e;
    }

    my $items_completed   = $i + 1;
    my $seconds_remaining = int( ( time - $start ) / $items_completed * ( $total - $items_completed ) );

    my $hours   = int( $seconds_remaining / 60 / 60 );
    my $minutes = int( ( $seconds_remaining - $hours * 60 * 60 ) / 60 );
    my $seconds = ( $seconds_remaining - $hours * 60 * 60 - $minutes * 60 );

    printf "%5d of %5d %3d%% %3d:%02d:%02d => %s\n",
        $items_completed,
        $total,
        int( $items_completed / $total * 100 ),
        $hours,
        $minutes,
        $seconds,
        $chapter->{file};
}

sub shuffle (@items) {
    return @items if ( $opt->{norandom} );
    return map { $_->[0] } sort { $a->[1] <=> $b->[1] } map { [ $_, rand() ] } @items;
}

=head1 NAME

fetch_gateway_html.pl - Fetch the HTML source of Bible Gateway content

=head1 SYNOPSIS

    fetch_gateway_html.pl OPTIONS
        -d, --dir      DIRECTORY          # default: ./gateway_html
        -s, --status   FILE               # default: ./local/fetch.gateway.status.json
        -w, --wait     SECONDS            # default: 1
        -b, --bible    BIBLE_TRANSLATION  # default: (all available)
        -n, --norandom
        -h, --help
        -m, --man

=head1 DESCRIPTION

This program will fetch the HTML source of Bible Gateway content and save it
locally, tracking progress via a status file.

=head2 -d, --dir

This is the directory where HTML content (one chapter per file) are stored. It
defaults to "./gateway_html". Files are stored in a tree in the form:

    TRANSLATION/BOOK/TRANSLATION_BOOK_CHAPTER.html

=head2 -s, --status

This is the location of the status file, saved as JSON. It defaults to
"./local/fetch.status.json".

=head2 -w, --wait

The number of seconds to wait between requests to Bible Gateway. Defaults to 1.

=head2 -b, --bible

Translations or translations (by acronym) to fetch. Defaults to all available.

=head2 -n, --norandom

If not set (which is the default), queries to Bible Gateway are mostly
randomized. Otherwise, they'll be performed in order.
