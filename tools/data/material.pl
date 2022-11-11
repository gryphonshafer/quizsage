#!/usr/bin/env perl
use exact -cli, -conf;
use Mojo::ByteStream;
use Mojo::File 'path';
use Mojo::JSON 'encode_json';
use Text::Unidecode 'unidecode';
use Omniframe;

my $opt      = options( qw{ bible|b=s@ obml|o=s size|s=i } );
my $obml_dir = $opt->{obml} || conf->get( qw{ config_app root_dir } ) . '/' . conf->get( 'data', 'obml');

my %bibles = map { uc($_) => 1 } @{ $opt->{bible} || [] };
my @bibles = grep {
    my $bible = $_;
    grep { $bible eq $_ } @{ path($obml_dir)->list({ dir => 1 })->map('basename')->to_array };
} keys %bibles;

pod2usage('Must supply at least 1 valid Bible translation by acronym') unless (@bibles);

my $dq        = Omniframe->with_roles('+Database')->new->dq('material');
my $bible_put = $dq->sql('INSERT INTO bible (acronym) VALUES (?)');
my $book_put  = $dq->sql('INSERT INTO book (name) VALUES (?)');

$opt->{size} ||= 300;

my @verse_insert_cache;
my ( $verse_put_batch, $verse_put_single ) = map {
    $dq->sql(
        q{
            INSERT OR IGNORE INTO verse (
                bible_id, book_id, chapter, verse, text, string, words
            ) VALUES
        } . join( ',', ( '( ?, ?, ?, ?, ?, ?, ? )' ) x $_ )
    )
} ( $opt->{size}, 1 );

my $bibles = { map { @$_ } @{ $dq->sql('SELECT acronym, bible_id FROM bible')->run->all } };
my $books  = { map { @$_ } @{ $dq->sql('SELECT name, book_id FROM book')->run->all } };

my $last_book = '';
for my $bible (@bibles) {
    path( $obml_dir . '/' . $bible )->list_tree->grep( qr/\.obml$/ )->each( sub {
        my $obml = unidecode( Mojo::ByteStream->new( $_->slurp )->decode->to_string );
        my ( $book, $chapter ) = $obml =~ /~\s*([^~]+?)\s*(\d*)\s*~/ms;
        $chapter ||= 1;

        unless ( $last_book eq "$bible $book" ) {
            print "$bible $book\n";
            $last_book = "$bible $book";
        }

        $obml =~ s/(\r?\n\r?\n[ ]*\|\d+\|)/$1/msg; # replace paragraph breaks
        $obml =~ s/~[^~]*?~//msg;                  # remove material references
        $obml =~ s/=+[^=]*?=+//msg;                # remove headers
        $obml =~ s/[\*\^]//msg;                    # remove red text and italic
        $obml =~ s/\r?\n\s*#.*\r?\n/\n/msg;        # remove line comments

        # remove crossreferences and footnotes
        $obml =~ s/([\}\]])\s+([\.\?\!\,\;\:])/$1$2/msg;
        $obml =~ s/\{[^\}]*?\}//msg;
        $obml =~ s/\[[^\]]*?\]//msg;

        # remove extraneous spaces
        $obml =~ s/\s+/ /msg;
        $obml =~ s/(^\s+|\s+$)//msg;

        for ( split( /(?=\|\d+\|)/, $obml ) ) {
            s/\s+$//msg;
            s/\|(?<verse>\d+)\|\s*//;

            my ( $verse, $text ) = ( $+{verse}, $_ );

            s/(\W)'(\w.*?\w)'(\W)/$1$2$3/g;
            s/[^A-Za-z0-9'\-]/ /gi;
            s/(?<!\w)'/ /g;
            s/\-{2,}/ /g;
            s/\s+/ /g;
            s/(?:^\s|\s$)//g;

            my @words = split( /\s/, lc($_) );

            $bibles->{$bible} //= $bible_put->run($bible)->up->last_insert_id;
            $books->{$book}   //= $book_put->run($book)->up->last_insert_id;

            push( @verse_insert_cache, [
                $bibles->{$bible},
                $books->{$book},
                $chapter,
                $verse,
                $text,
                ' ' . join( ' ', @words ) . ' ',
                encode_json( \@words ),
            ] );

            if ( @verse_insert_cache == $opt->{size} ) {
                $verse_put_batch->run( map { @$_ } @verse_insert_cache );
                @verse_insert_cache = ();
            }
        }
    } );
}

$verse_put_single->run(@$_) while ( $_ = shift @verse_insert_cache );

=head1 NAME

material.pl - Open OBML source content and save to a material SQLite database

=head1 SYNOPSIS

    material.pl OPTIONS
        -b, --bible BIBLE_TRANSLATION
        -o, --obml  OBML_DIRECTORY     # default: config setting
        -s, --size  INSERT_CACHE_SIZE  # detault: 300
        -h, --help
        -m, --man

=head1 DESCRIPTION

This program will open OBML source content and save to a material SQLite
database.

=head2 -b, --bible

One or more Bible translation acronyms.

=head2 -o, --obml

If defined, this stipulates the directory where OBML files should be stored. If
not defined, the C<data/obml> string config setting will be used and assumed to
be a directory relative to the project's root directory. Files are expected to
be stored in a tree in the form:

    TRANSLATION/BOOK/TRANSLATION_BOOK_CHAPTER.html

=head2 -s, --size

Sets the size of the verse insert cache. Inserting each verse into the database
one by one is slower than batching them via a cache. The default size is 300
verses per single insert.
