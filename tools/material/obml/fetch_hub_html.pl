#!/usr/bin/env perl
use exact -cli;
use File::Path 'make_path';
use Mojo::File 'path';
use Mojo::UserAgent;
use Mojo::JSON qw( encode_json decode_json );

my $opt = options( qw{ dir|d=s wait|w=i bible|b=s@ structure|s=s } );

$opt->{dir}       ||= './hub_html';
$opt->{wait}      //= 1;
$opt->{structure} //= './local/fetch.hub.structure.json';

$opt->{dir} = path( $opt->{dir} );

my $url = Mojo::URL->new('https://biblehub.com');
my $ua  = Mojo::UserAgent->new( max_redirects => 3 );

$opt->{structure} = path( $opt->{structure} );
$opt->{structure}->dirname->make_path;

my $structure;
$structure = decode_json $opt->{structure}->slurp if ( -f $opt->{structure} );

sub save {
    $opt->{structure}->spurt( encode_json $structure );
}

my $gets_count;
sub result($path) {
    sleep $opt->{wait} if ($gets_count++);
    my $this_url = $url->clone->path($path);
    say $this_url->to_string;
    return $ua->get($this_url)->result;
}

for my $bible ( $opt->{bible}->@* ) {
    unless ( $structure->{ uc($bible) } ) {
        $structure->{ uc($bible) } = result( lc($bible) . '/cmenus/bookmenu.htm' )->dom
            ->find('td[width="50%"] div.container li')->map( sub {
                my $path = $_->at('a')->attr('href');
                +{
                    display => $_->at('h3')->text,
                    path    => ( ( $path =~ m|/| ) ? ( split( '/', $path ) )[1] : $path ),
                };
            } )->to_array;
        save;
    }

    for my $book ( grep { not $_->{num_chapters} } $structure->{ uc($bible) }->@* ) {
        my $chapters = result( lc($bible) . '/cmenus/' . $book->{path} )->dom
            ->find('li')->map( sub { $_->at('h3')->text } )->grep(qr/^\d+$/);

        $book->{chapters}     = [ ( $chapters->size ) ? $chapters->to_array->@* : 1 ];
        $book->{num_chapters} = $chapters->size || 1;

        save;
    }
}

for my $bible ( keys $structure->%* ) {
    for my $book ( $structure->{$bible}->@* ) {
        for my $chapter ( $book->{chapters}->@* ) {
            ( my $book_name_node = $book->{display} ) =~ s/\s+/_/g;

            my $target = $opt->{dir}->child( join( '/',
                uc($bible),
                $book_name_node,
                join( '_', uc($bible), $book_name_node, $chapter ) . '.html'
            ) );

            next if ( -f $target );

            print $target->to_string, ' <= ';
            $target->dirname->make_path;
            $target->spurt( result( lc($bible) . '/' . $book->{path} . '/' . $chapter . '.htm' )->body );
        }
    }
}

=head1 NAME

fetch_hub_html.pl - Fetch the HTML source of Bible Hub content

=head1 SYNOPSIS

    fetch_hub_html.pl OPTIONS
        -d, --dir       DIRECTORY          # default: ./hub_html
        -w, --wait      SECONDS            # default: 1
        -b, --bible     BIBLE_TRANSLATION  # default: (all available)
        -s, --structure STRUCTURE_JSON     # default: ./local/fetch.hub.structure.json
        -h, --help
        -m, --man

=head1 DESCRIPTION

This program will fetch the HTML source of Bible Hub content and save it
locally, tracking progress via a status file.

=head2 -d, --dir

This is the directory where HTML content (one chapter per file) are stored. It
defaults to "./hub_html". Files are stored in a tree in the form:

    TRANSLATION/BOOK/TRANSLATION_BOOK_CHAPTER.html

=head2 -w, --wait

The number of seconds to wait between requests to Bible Hub. Defaults to 1.

=head2 -b, --bible

Translations or translations (by acronym) to fetch. Defaults to all available.

=head2 -s, --structure

JSON file to store/cache structure information.
