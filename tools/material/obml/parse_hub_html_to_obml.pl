#!/usr/bin/env perl
use exact -cli;
use Bible::OBML;
use File::Path 'make_path';
use Mojo::ByteStream;
use Mojo::Collection 'c';
use Mojo::DOM;
use Mojo::File 'path';
use Parallel::ForkManager;

my $opt = options( qw{ source|s=s obml|o=s bible|b=s@ target|t=s force|f forks|k } );

$opt->{source} ||= './hub_html';
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
            $obml = parse(
                Mojo::ByteStream->new(
                    $item->{source}->slurp
                )->decode
            )
        }
        catch ($e) {
            $e =~ s/\s+at\s+.+\s+line\s+\d+\.//;
            warn $e;
            kill 'INT', $ppid;
            exit;
        }

        make_path( $item->{target}->dirname );

        $item->{target}->spew(
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

sub _retag ( $tag, $retag ) {
    $tag->tag($retag);
    delete $tag->attr->{$_} for ( keys %{ $tag->attr } );
}

sub parse ($html) {
    return unless ($html);

    my $dom = Mojo::DOM->new($html);

    my $reference = $dom->at('div#topheading');
    my $chapter   = $dom->find('div.chap');

    croak('source appears to be invalid; check your inputs')
        unless ( $reference and $reference->text and $chapter->size == 1 );

    $chapter = $chapter->first;
    _retag( $chapter, 'obml' );

    ( $reference = $reference->text ) =~ s/(?:^\s+|\s+$)//g;
    $chapter->children->first->prepend( '<reference>' . $reference . '</reference>' );

    $chapter->find('p.sectionhead, p.hdg, p.heading')->each( sub { _retag( $_, 'header' ) } );
    $chapter->find(
        'p.minorsectionhead, p.acrostic, p.ihdg, p.pshdg, p.subhdg, p.suphdg',
    )->each( sub { _retag( $_, 'sub_header' ) } );

    $chapter->find('span.reftext')->each( sub {
        $_->content( $_->all_text );
        _retag( $_, 'verse_number' );
    } );

    $chapter->find('span.red, span.woc')->each( sub { _retag( $_, 'woj' ) } );
    $chapter->find('hr, a[name]')->each('remove');

    if ( my $footnotes = $chapter->at('div#fnlink, span.mainfootnotes') ) {
        my $child_nodes = $footnotes->child_nodes;
        $footnotes->remove;
        $footnotes = {};
        my $buffer = c;
        while ( my $node = shift @$child_nodes ) {
            unless ( ( $node->tag // '' ) eq 'br' ) {
                push( @$buffer, $node );
            }
            elsif ( $buffer->grep( sub { ( $_->attr('class') // '' ) eq 'fnverse' } )->size ) {
                my $block = $buffer->grep( sub {
                    ( $_->attr('class') // '' ) ne 'thin' and
                    ( $_->attr('class') // '' ) ne 'fnverse' and
                    ( $_->text // '' ) ne 'Footnotes:'
                } );
                shift @$block if ( $block->first->all_text !~ /\S/ );

                my $id = ( shift @$block )->all_text;
                ( my $footnote = $block->map('to_string')->join('')->to_string ) =~ s/(^\s+|\s+$)//g;
                $footnote = Mojo::DOM->new($footnote);
                $footnote->find('i')->each( sub { _retag( $_, 'i' ) } );
                $footnote->find('a, span')->each('strip');

                $footnotes->{$id} = $footnote->to_string;
                $buffer = c;
            }
        }

        $chapter->find('span.fn, span[class*="footnote"]')->each( sub {
            $_->replace( '<footnote>' . $footnotes->{ $_->all_text } . '</footnote>' );
        } );
    }

    $bible_ref->acronyms(1)->require_chapter_match(1)->require_book_ucfirst(1);
    $chapter->find('br + span.cross')->each( sub {
        $_->previous('br')->remove;
        $_->replace(
            '<crossref>' .
            $bible_ref->clear->in( $_->find('a')->map('text')->join('; ') )->refs .
            '</crossref>'
        );
    } );

    $chapter->find(
        join( ', ',
            map { 'p.indent' . $_, 'p.list' . $_, 'p.tab' . $_ }
            map { $_, 'red' . $_, $_ . 'stline', $_ . 'stlinered' } 1 .. 9
        )
    )->each( sub {
        my $red = $_->attr('class') =~ /red/;
        $_->attr('class') =~ /(\d)/;
        _retag( $_, 'indent' );
        $_->attr( 'level', $1 );
        $_->content( '<woj>' . $_->content . '</woj>' ) if $red;
    } );

    $chapter->find('p.selah, div.inscrip')->each( sub {
        ( my $content = $_->content ) =~ s/(^\s+|\s+$)//g;
        $_->replace( '<p><i>' . $content . '</i></p>' )
    } );

    $chapter->find('p')->each( sub { _retag( $_, 'p' ) } );
    $chapter->find('span, br')->each('remove');

    while( my $first_indent = $chapter->find('indent')->grep( sub { $_->parent->tag ne 'p' } )->first ) {
        my $buffer = c;
        while ( $first_indent->next and $first_indent->next->tag eq 'indent' ) {
            push( @$buffer, $first_indent->next );
            $first_indent->next->remove;
        }
        $first_indent->replace( '<p>' . join( '<br>', $first_indent, @$buffer ) . '</p>' );
    }

    $chapter->find('div')->each('strip');

    $chapter->find('p, indent')->each( sub {
        ( my $content = $_->content ) =~ s/(^\s+|\s+$)//g;
        $_->content($content) if ( $content ne $_->content );
    } );

    my $obml = $bible_obml->html( $chapter->to_string )->obml;
    $obml =~ s/([a-z])([:;,!?])([A-Za-z])/$1$2 $3/g;
    return $obml;
}

=head1 NAME

parse_hub_html_to_obml.pl - Parse raw HTML source of Bible Hub content

=head1 SYNOPSIS

    parse_hub_html_to_obml.pl OPTIONS
        -s, --source DIRECTORY          # default: ./hub_html
        -o, --obml   DIRECTORY          # default: ./obml
        -b, --bible  BIBLE_TRANSLATION  # default: (all available)
        -t, --target REGEX
        -f, --force
        -k, --forks  INTEGER            # default: 16
        -h, --help
        -m, --man

=head1 DESCRIPTION

This program will parse the HTML source of Bible Hub content and save it
as OBML.

=head2 -s, --source

This is the directory where HTML content (one chapter per file) are stored. It
defaults to "./hub_html". Files are stored in a tree in the form:

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
