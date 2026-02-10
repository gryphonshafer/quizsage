#!/usr/bin/env perl
use exact -conf, -cli;
use JavaScript::QuickJS;
use Mojo::DOM;
use Mojo::File 'path';
use QuizSage::Model::Label;

my $opt = options( qw{ cbq|c=s doc|d=s } );
pod2usage('"cbq" value must be provided') unless ( $opt->{cbq} );
$opt->{doc} //= 'CBQ_system/seasonal_material.md';

my $code = Mojo::DOM->new(
    path( $opt->{cbq} . '/docs/' . $opt->{doc} )->slurp('UTF-8')
)->at('script')->text;
$code =~ s/window\..+/rotations;/s;
my $rotations = JavaScript::QuickJS->new->eval($code);

my $label = QuizSage::Model::Label->new;
my $dq = $label->dq('material');
my $bibles = $dq->sql('SELECT acronym FROM bible WHERE acronym != "HWP" ORDER BY acronym')->run->column;
my $sth_count = $dq->sql(q{
    SELECT COUNT(*)
    FROM verse
    JOIN bible USING (bible_id)
    JOIN book  USING (book_id)
    WHERE
        bible.acronym = ? AND
        book.name     = ? AND
        verse.chapter = ? AND
        verse.verse   = ?
});

for my $league (@$rotations) {
    say $league->[0];

    for my $preset ( $league->[1]->@* ) {
        say ' ' x 4, $preset->[0];

        for my $season ( map { $preset->[$_] } 2 .. @$preset - 1 ) {
            my $range = join( '; ', map { $season->[$_] } 1 .. @$season - 1 );
            say ' ' x 8, $range;

            my $refs = [ map { [
                /^(.+?)\s+(\d+):(\d+)$/
            ] } $label->versify_refs($range)->@* ];

            my $counts = {};
            my $niv;
            for my $bible (@$bibles) {
                my $count = 0;
                $count += $sth_count->run( $bible, @$_ )->value for (@$refs);
                push( @{ $counts->{$count} }, $bible );
                $niv = $count if ( $bible eq 'NIV' );
            }

            my @counts = sort { $a <=> $b } keys %$counts;
            my ($commonest) =
                map { $_->[0] }
                sort { $b->[1] <=> $a->[1] }
                map { [ $_, scalar( @{ $counts->{$_} } ) ] }
                keys %$counts;

            printf ' ' x 12 . "%4d %4d %4d %4d\n", $commonest, $niv, $counts[0], $counts[-1];
        }
    }
}

=head1 NAME

verses_count.pl - Counts season material preset verses

=head1 SYNOPSIS

    verses_count.pl OPTIONS
        -c, --cbq  PATH          # required
        -d, --doc  PATH_TO_FILE  # default: "CBQ_system/seasonal_material.md"
        -h, --help
        -m, --man

=head1 DESCRIPTION

This program will count season material preset verses.

=head2 -c, --cbq

Path to the CBQz.org web site project root directory.

=head2 -d, --doc

Relative path (inside the documentation directory) to the season materials
Markdown file. Default value is "CBQ_system/seasonal_material.md".
