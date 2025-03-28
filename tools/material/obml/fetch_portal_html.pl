#!/usr/bin/env perl
use exact -cli;
use File::Path 'make_path';
use Mojo::File 'path';
use Mojo::URL;
use Mojo::UserAgent;
use Mojo::JSON qw( to_json from_json );

my $opt = options( qw{ dir|d=s wait|w=i bible|b=s@ structure|s=s } );

$opt->{dir}       ||= './portal_html';
$opt->{wait}      //= 1;
$opt->{structure} //= './local/fetch.portal.structure.json';

$opt->{dir} = path( $opt->{dir} );

my $url = Mojo::URL->new('https://bibleportal.com');
my $ua  = Mojo::UserAgent->new( max_redirects => 3 );

$opt->{structure} = path( $opt->{structure} );
$opt->{structure}->dirname->make_path;

my $structure;
$structure = from_json $opt->{structure}->slurp('UTF-8') if ( -f $opt->{structure} );

sub save {
    $opt->{structure}->spew( to_json($structure), 'UTF-8' );
}

my $gets_count;
sub result( $path, $query = undef ) {
    sleep $opt->{wait};
    my $this_url = $url->clone->path($path);
    $this_url->query($query) if ($query);
    say $this_url->to_string;
    return $ua->get($this_url)->result;
}

unless ($structure) {
    $structure = {
        books => [
            map { +{
                name     => $_->{book_names}{en},
                chapters => $_->{chapters},
            } }
            $ua->get('https://api2.bibleportal.com/api/books/list')->result->json->{data}->@*
        ],
        versions => result('/versions')->dom
            ->find('h4')->grep( sub { $_->text eq 'English' } )->first->next
            ->find('a')->map( sub {
                ( my $name = $_->text ) =~ s/\s+\(([^)]+)\)//;
                return {
                    name    => $name,
                    acronym => $1,
                };
            } )->to_array,
    };
    save;
}

$structure->{versions} = [
    grep { defined }
    map {
        my $acronym = $_;
        my ($version) = grep { $_->{acronym} eq $acronym } $structure->{versions}->@*;
        $version;
    }
    $opt->{bible}->@*
] if ( $opt->{bible} );

for my $version ( $structure->{versions}->@* ) {
    for my $book ( $structure->{books}->@* ) {
        for my $chapter ( 1 .. $book->{chapters} ) {
            # say join(' ', $version->{acronym}, $book->{name}, $chapter );

            ( my $book_name_path = $book->{name} ) =~ s/\s+/_/g;
            my $target = path(
                join( '/',
                    $opt->{dir}, $version->{acronym}, $book_name_path,
                    join( '_', $version->{acronym}, $book_name_path, $chapter ) . '.html',
                )
            );

            next if ( -f $target );

            $target->dirname->make_path;
            $target->spew(
                result(
                    '/passage',
                    {
                        version => $version->{acronym},
                        search  => $book->{name} . ' ' . $chapter,
                    },
                )->body,
                'UTF-8',
            );
        }
    }
}

=head1 NAME

fetch_portal_html.pl - Fetch the HTML source of Bible Portal content

=head1 SYNOPSIS

    fetch_portal_html.pl OPTIONS
        -d, --dir       DIRECTORY          # default: ./portal_html
        -w, --wait      SECONDS            # default: 1
        -b, --bible     BIBLE_TRANSLATION  # default: (all available)
        -s, --structure STRUCTURE_JSON     # default: ./local/fetch.portal.structure.json
        -h, --help
        -m, --man

=head1 DESCRIPTION

This program will fetch the HTML source of Bible Portal content and save it
locally, tracking progress via a status file.

=head2 -d, --dir

This is the directory where HTML content (one chapter per file) are stored. It
defaults to "./portal_html". Files are stored in a tree in the form:

    TRANSLATION/BOOK/TRANSLATION_BOOK_CHAPTER.html

=head2 -w, --wait

The number of seconds to wait between requests to Bible Portal. Defaults to 1.

=head2 -b, --bible

Translations or translations (by acronym) to fetch. Defaults to all available.

=head2 -s, --structure

JSON file to store/cache structure information.
