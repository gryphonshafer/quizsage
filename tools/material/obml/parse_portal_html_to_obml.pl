#!/usr/bin/env perl
use exact -cli;
use Bible::OBML;
use Bible::Reference;
use File::Path 'make_path';
use Mojo::Collection 'c';
use Mojo::DOM;
use Mojo::File 'path';
use Parallel::ForkManager;
use Mojo::JSON 'from_json';

my $opt = options( qw{ source|s=s obml|o=s bible|b=s@ target|t=s force|f forks|k } );

$opt->{source} ||= './portal_html';
$opt->{obml}   ||= './obml';
$opt->{forks}  ||= 16;

$opt->{$_}    = path( $opt->{$_} ) for ( qw( source obml ) );
$opt->{bible} = [ map { uc } @{ $opt->{bible} } ];

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

my $bible_obml = Bible::OBML->new;
my $bible_ref  = Bible::Reference->new( bible => 'Protestant' );

$files->each( sub ( $item, $count ) {
    if ( not $pm->start ) {
        my $obml;
        try {
            $obml = parse( $item->{source}->slurp('UTF-8') );
        }
        catch ($e) {
            $e =~ s/\s+at\s+.+\s+line\s+\d+\.//;
            warn $e;
            kill 'INT', $ppid;
            exit;
        }

        make_path( $item->{target}->dirname );

        $item->{target}->spew( $obml . "\n", 'UTF-8' );

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

sub _retag ( $tag, $retag ) {
    $tag->tag($retag);
    delete $tag->attr->{$_} for ( keys %{ $tag->attr } );
}

sub parse ($html) {
    return unless ($html);

    my $data = from_json(
        Mojo::DOM->new($html)->at('script#__NEXT_DATA__')->text
    )->{props}{pageProps}{result}{data}[0]{results}[0];

    my $text = '~' . $data->{reference} . '~' . "\n\n";
    for my $passage ( $data->{passages}->@* ) {
        $passage->{content} =~ s/(?:^\s+|\s+$)//g;
        $passage->{content} =~ s|<i>(.+?)</i>|^$1^|gi;
        $passage->{content} =~ s|<woj>(.+?)</woj>|*$1*|gi;

        $bible_ref->acronyms(1)->require_chapter_match(1)->require_book_ucfirst(1);

        my @crs = map {
            s/(\d)\.(\d)/$1:$2/g;
            s/(\d)([A-z])/$1 $2/g;
            s/\./ /g;
            s/([,;])/$1 /g;
            s/\s+/ /g;
            $bible_ref->clear->in($_)->refs;
        } ( $passage->{cross_references} ) ? split( /\|\|/, $passage->{cross_references} ) : ();

        my @fts = map {
            s/(?:^\s+|\s+$)//g;
            s|<i>(.+?)</i>|^$1^|gi;
            s|<woj>(.+?)</woj>|*$1*|gi;
            $bible_ref->clear->in($_)->as_text;
        } ( $passage->{footnotes} ) ? split( /\|\|/, $passage->{footnotes} ) : ();

        $passage->{content} =~ s|<cr>(.+?)</cr>| '{' . $crs[ $1 - 1 ] . '}' |egi;
        $passage->{content} =~ s|<ft>(.+?)</ft>| '[' . $fts[ $1 - 1 ] . ']' |egi;

        if ( $passage->{subhead} ) {
            $text .= "\n\n= " . $passage->{content} . " =\n\n";
        }
        else {
            $text .= "\n\n" if ( $passage->{np} );
            $text .= ( ( $text =~ /\S$/ ) ? ' ' : '' ) . '|' . $passage->{verse} . '| ';
            $text .= $passage->{content};
        }
    }

    $text =~ s~</?table>~~sgi;
    $text =~ s|<td>(.+?)</td>|$1 |sgi;
    $text =~ s|<tr>(.+?)</tr>|    $1|sgi;
    $text =~ s|<pb/?>|\n\n|gi;
    $text =~ s|<br/?>|\n|gi;

    $text =~ s|<indent>(.+?)</indent>|    $1|sgi;

    my $poetry = sub ($block) {
        $block =~ s/^/    /;
        $block =~ s/\n/\n    /g;
        $block;
    };

    $text =~ s|<poetry>(.+?)</poetry>|$poetry->($1)|sgei;
    $text =~ s|<smallcap>(.+?)</smallcap>|\\$1\\|sgi;
    $text =~ s|</?list\d*>||gi;
    $text =~ s|<hang(\d+)>(\s*)(.+?)</hang\d+>|
        ( ( length $2 ) ? $2 : "\n" ) . ( ' ' x ( 4 * $1 - 1 ) ) . $3 . ""
    |sgei;
    $text =~ s|<center>(\s*)(.+?)</center>| ( ( length $1 ) ? $1 : '    ' ) . $2 |sgie;
    $text =~ s|<[^>]*>||sg;

    $text =~ s/([a-z])([:;,!?])([A-Za-z])/$1$2 $3/g;

    return $bible_obml->obml($text)->obml;
}

=head1 NAME

parse_portal_html_to_obml.pl - Parse raw HTML source of Bible Portal content

=head1 SYNOPSIS

    parse_portal_html_to_obml.pl OPTIONS
        -s, --source DIRECTORY          # default: ./portal_html
        -o, --obml   DIRECTORY          # default: ./obml
        -b, --bible  BIBLE_TRANSLATION  # default: (all available)
        -t, --target REGEX
        -f, --force
        -k, --forks  INTEGER            # default: 16
        -h, --help
        -m, --man

=head1 DESCRIPTION

This program will parse the HTML source of Bible Portal content and save it
as OBML.

=head2 -s, --source

This is the directory where HTML content (one chapter per file) are stored. It
defaults to "./portal_html". Files are stored in a tree in the form:

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
