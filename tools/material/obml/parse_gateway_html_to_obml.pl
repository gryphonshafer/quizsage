#!/usr/bin/env perl
use exact -cli;
use Bible::OBML;
use Bible::OBML::Gateway;
use File::Path 'make_path';
use Mojo::ByteStream;
use Mojo::File 'path';
use Parallel::ForkManager;

my $opt = options( qw{ source|s=s obml|o=s bible|b=s@ target|t=s force|f forks|k } );

$opt->{source} ||= './gateway_html';
$opt->{obml}   ||= './obml';
$opt->{forks}  ||= 16;

$opt->{$_}    = path( $opt->{$_} ) for ( qw( source obml ) );
$opt->{bible} = [ map { uc } @{ $opt->{bible} } ];

my $bg = Bible::OBML::Gateway->new;
my $o  = Bible::OBML->new;

my $files = $opt->{source}
    ->list_tree
    ->map( sub {
        m|/(?<bible>[^/]+)/(?<book>[^/]+)/(?<name>[^/]+)\.html$|;
        +{
            %+,
            source => $_,
            target => $opt->{obml}->child( join( '/', $+{bible}, $+{book}, $+{name} . '.obml' ) ),
        };
    } )
    ->grep( sub ($item) {
        ( $opt->{force} or not -f $_->{target} ) and
        ( not @{ $opt->{bible} } or grep { $_ eq $item->{bible} } @{ $opt->{bible} } ) and
        ( not $opt->{target} or $_->{target} =~ /$opt->{target}/ )
    } );

my ( $start, $total, $ppid ) = ( time, $files->size, $$ );

my $pm = Parallel::ForkManager->new( $opt->{forks} );

$SIG{INT} = sub {
    print "\n";
    exit;
};

$files->each( sub ( $item, $count ) {
    if ( not $pm->start ) {
        my $obml;
        try {
            $obml = $o->html(
                $bg->parse(
                    Mojo::ByteStream->new(
                        $item->{source}->slurp
                    )->decode
                )
            )->obml;
        }
        catch ($e) {
            $e =~ s/\s+at\s+.+\s+line\s+\d+\.//;
            warn $e;
            kill 'INT', $ppid;
            exit;
        }

        make_path( $item->{target}->dirname );

        $item->{target}->spurt(
            Mojo::ByteStream->new(
                $obml
            )->encode . "\n"
        );

        my $seconds_remaining = int( ( time - $start ) / $count * ( $total - $count ) );

        my $hours   = int( $seconds_remaining / 60 / 60 );
        my $minutes = int( ( $seconds_remaining - $hours * 60 * 60 ) / 60 );
        my $seconds = ( $seconds_remaining - $hours * 60 * 60 - $minutes * 60 );

        printf "%5d of %5d %3d%% %3d:%02d:%02d => %s\n",
            $count,
            $total,
            int( $count / $total * 100 ),
            $hours,
            $minutes,
            $seconds,
            $item->{target};

        $pm->finish;
    }
} );

$pm->wait_all_children;

=head1 NAME

parse_gateway_html_to_obml.pl - Parse raw HTML source of Bible Gateway content

=head1 SYNOPSIS

    parse_gateway_html_to_obml.pl OPTIONS
        -s, --source DIRECTORY          # default: ./gateway_html
        -o, --obml   DIRECTORY          # default: ./obml
        -b, --bible  BIBLE_TRANSLATION  # default: (all available)
        -t, --target REGEX
        -f, --force
        -k, --forks  INTEGER            # default: 16
        -h, --help
        -m, --man

=head1 DESCRIPTION

This program will fetch the HTML source of Bible Gateway content and save it
locally, tracking progress via a status file.

=head2 -s, --source

This is the directory where HTML content (one chapter per file) are stored. It
defaults to "./gateway_html". Files are stored in a tree in the form:

    TRANSLATION/BOOK/TRANSLATION_BOOK_CHAPTER.html

=head2 -o, --obml

This is the directory where OBML content (one chapter per file) are stored. It
defaults to "./obml". Files are stored in a tree in the form:

    TRANSLATION/BOOK/TRANSLATION_BOOK_CHAPTER.obml

=head2 -b, --bible

Translations or translations (by acronym) to fetch. Defaults to all available.

=head2 -t, --target

If set, this regex will be used to check against would-be target files. For any
match, processing happens.

=head2 -f, --force

Normally, if the target already exists, processing is skipped. Set this flag to
process anyway.

=head2 -k, --forks

Number of forked processes to run for parallel processing. Defaults to 16.
