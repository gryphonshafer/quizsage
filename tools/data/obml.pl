#!/usr/bin/env perl
use exact -cli, -conf;
use Mojo::ByteStream;
use Bible::OBML::Gateway;
use Bible::Reference;
use File::Path 'make_path';
use Mojo::File 'path';

my $opt = options( qw{ bible|b=s@ range|r=s obml|o=s sleep|s=i } );
$opt->{sleep} //= 4;

my $obml_parent_dir = $opt->{obml} ||
    conf->get( qw{ config_app root_dir } ) . '/' . conf->get( 'data', 'obml');

my $gw           = Bible::OBML::Gateway->new;
my @translations = map { map { $_->{acronym} } @{ $_->{translations} } } @{ $gw->translations };
my %bibles       = map { uc($_) => 1 } @{ $opt->{bible} || [] };
my @bibles       = grep {
    my $bible = $_;
    grep { $bible eq $_ } @translations;
} keys %bibles;

pod2usage('Must supply at least 1 valid Bible translation by acronym') unless (@bibles);

my $ref = Bible::Reference->new( add_detail => 1 );

for my $bible (@bibles) {
    my $structure = $gw->structure($bible);
    my $bibles    = $ref->identify_bible( map { $_->{display} } @$structure );

    $ref->bible(
        ( grep { $_->{name} eq 'Protestant' } @$bibles ) ? 'Protestant' :
        ( grep { $_->{name} eq 'Catholic'   } @$bibles ) ? 'Catholic'   :
        ( grep { $_->{name} eq 'Orthodox'   } @$bibles ) ? 'Orthodox'   : undef
    );

    my $chapters = ( $opt->{range} )
        ? [ map { [ /^(.+)\s(\d+)/ ] } @{ $ref->clear->in( $opt->{range} )->as_chapters } ]
        : [ map {
            my $book = $_->{display};
            map { [ $book, $_ ] } 1 .. @{ $_->{chapters} }
        } @$structure ];

    next unless (@$chapters);

    $gw->translation($bible);

    my $bible_path = join( '/', $obml_parent_dir, $bible );
    make_path($bible_path) unless ( -d $bible_path );

    for my $chapter (@$chapters) {
        ( my $book_filename = $chapter->[0] ) =~ s/\s+/_/g;
        my $path = join( '/', $obml_parent_dir, $bible, $book_filename );
        my $file = $path . '/' . join( '_', $bible, $book_filename ) . '_' . $chapter->[1] . '.obml';

        next if ( -f $file );
        make_path($path) unless ( -d $path );

        say join( ' ', @$chapter );

        path($file)->spurt(
            Mojo::ByteStream->new(
                $gw->get( join( ' ', @$chapter ) )->obml . "\n"
            )->encode
        );

        say ' ' x 4, $file;

        sleep $opt->{sleep} if ( $opt->{sleep} );
    }
}

=head1 NAME

obml.pl - Get source Bible Gateway content and save as OBML

=head1 SYNOPSIS

    obml.pl OPTIONS
        -b, --bible BIBLE_TRANSLATION
        -o, --obml  OBML_DIRECTORY     # default: config setting
        -r, --range REFERENCE_RANGE
        -s, --sleep SECONDS            # default: 4
        -h, --help
        -m, --man

=head1 DESCRIPTION

This program will get source Bible Gateway content and save it as as OBML files.

=head2 -b, --bible

One or more Bible translation acronyms.

=head2 -o, --obml

If defined, this stipulates the directory where OBML files should be stored. If
not defined, the C<data/obml> string config setting will be used and assumed to
be a directory relative to the project's root directory. Files are stored in a
tree in the form:

    TRANSLATION/BOOK/TRANSLATION_BOOK_CHAPTER.html

=head2 -r, --range

If defined, this will limit the content to only the chapters specified in the
range.

=head2 -s, --sleep

Integer of number of seconds to sleep between chapter pulls. Defaults to 4.
