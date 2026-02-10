#!/usr/bin/env perl
use exact -conf, -cli;
use Mojo::File 'path';
use Mojo::DOM;
use QuizSage::Model::Label;

{
    my $setup = setup( options( qw{ print|p save|s file|f=s } ) );
    $setup->{opt}{file} //= 'translation_integration.md';
    $setup->{dq}->begin_work;

    delete_verses_not_included(
        get_removals_from_docs_table( $setup->{opt}{file} ),
        $setup,
    );

    trim_mid_verse_bracket_start( $_, $setup ) for (
        'Mark 9:45 HCSB',
        'Acts 24:6 AMP',
        'John 5:3 AMP HCSB NASB5',
    );

    split_verse_on_period( '2 Corinthians 13:12 HCSB NRSVA', $setup );

    merge_verses( $_, $setup ) for (
        '3 John 1:14 AMP ESV NASB NASB5 NLT NRSVA RSV',
        'Revelation 12:17 HCSB NLT NRSVA',
    );

    unless ( $setup->{opt}{save} ) {
        $setup->{dq}->rollback;
    }
    else {
        $setup->{dq}->commit;
    }
}

sub setup ( $opt = {} ) {
    my $label = QuizSage::Model::Label->new;
    my $dq    = $label->dq('material');

    return {
        opt   => $opt,
        label => $label,
        dq    => $dq,
        sth   => {
            delete_verse => $dq->sql('DELETE FROM verse WHERE verse_id = ?'),
            put_text     => $dq->sql('UPDATE verse SET text = ? WHERE verse_id = ?'),
            get_verse    => $dq->sql(q{
                SELECT verse.*
                FROM verse
                JOIN bible USING (bible_id)
                JOIN book  USING (book_id)
                WHERE
                    bible.acronym = ? AND
                    book.name     = ? AND
                    verse.chapter = ? AND
                    verse.verse   = ?
            }),
            put_verse => $dq->sql(q{
                INSERT INTO verse ( bible_id, book_id, chapter, verse, text )
                    VALUES ( ?, ?, ?, ?, ? )
            }),
        },
    };
}

sub get_removals_from_docs_table ($file) {
    my $table = Mojo::DOM->new(
        path(
            conf->get( qw( config_app root_dir ) ) . '/docs/' . $file
        )->slurp('UTF-8')
    )->at('table#content_differences');

    my $bibles = $table->find('th:not(:first-child)')->map('text')->to_array;
    my $removals;

    $table->find('tbody tr')->each( sub {
        my $row = $_->find('td')->map('text')->to_array;
        my $ref = shift @$row;

        for my $i ( 0 .. @$row - 1 ) {
            push( @{ $removals->{$ref} }, $bibles->[$i] ) if ( lc( $row->[$i] ) ne 'included' );
        }
    } );

    return $removals;
}

sub delete_verses_not_included ( $removals = undef, $setup = undef ) {
    $removals //= get_removals();
    $setup    //= setup();

    say 'Delete not included...' if ( $setup->{opt}{print} );
    for my $range ( keys %$removals ) {
        for my $ref (
            map { [
                /^(.+?)\s(\d+):(\d+)$/
            ] } $setup->{label}->versify_refs($range)
        ) {
            for my $bible ( $removals->{$range}->@* ) {
                my $verse_h = $setup->{sth}{get_verse}->run( $bible, @$ref )->first({});
                if ($verse_h) {
                    say ' ' x 4, $ref->[0], ' ', $ref->[1], ':', $ref->[2], ' ', $bible
                        if ( $setup->{opt}{print} );
                    $setup->{sth}{delete_verse}->run( $verse_h->{verse_id} );
                }
            }
        }
    }
}

sub trim_mid_verse_bracket_start ( $simple_label, $setup = undef ) {
    $setup //= setup();

    my ( $book, $chapter, $verse, $bibles ) = $simple_label =~ /^(.+?)\s+(\d+):(\d+)\s*(.*)/;
    for my $bible ( split( /\s+/, $bibles ) ) {
        my $verse_h = $setup->{sth}{get_verse}->run( $bible, $book, $chapter, $verse )->first({});
        if ( $verse_h and $verse_h->{text} =~ /\W+\s*\(.+/ ) {
            if ( $setup->{opt}{print} ) {
                say 'Trim mid-verse bracket start ', $book, ' ', $chapter, ':', $verse, ' ', $bible;
                say ' ' x 4, '> ', $verse_h->{text};
            }
            $verse_h->{text} =~ s/\W+\s*\(.+/\./;
            say ' ' x 4, '> ', $verse_h->{text} if ( $setup->{opt}{print} );
            $setup->{sth}{put_text}->run( $verse_h->{text}, $verse_h->{verse_id} );
        }
    }
}

sub split_verse_on_period ( $simple_label, $setup = undef ) {
    $setup //= setup();

    say 'Split ', $simple_label, '...' if ( $setup->{opt}{print} );

    my ( $book, $chapter, $verse, $bibles ) = $simple_label =~ /^(.+?)\s+(\d+):(\d+)\s*(.*)/;
    for my $bible ( split( /\s+/, $bibles ) ) {
        my $verse_1 = $setup->{sth}{get_verse}->run( $bible, $book, $chapter, $verse     )->first({});
        my $verse_2 = $setup->{sth}{get_verse}->run( $bible, $book, $chapter, $verse + 1 )->first({});
        my $verse_3 = $setup->{sth}{get_verse}->run( $bible, $book, $chapter, $verse + 2 )->first({});

        next if $verse_3;

        say ' ' x 4, 'Copy second verse content into a third (new) verse' if ( $setup->{opt}{print} );
        $setup->{sth}{put_verse}->run(
            $verse_2->{bible_id}, $verse_2->{book_id}, $chapter, $verse + 2, $verse_2->{text},
        );

        if ( $setup->{opt}{print} ) {
            say ' ' x 4, 'Split first verse and save text into first and second verses';
            say ' ' x 8, '> ', $verse_1->{text};
        }

        my @text_parts = split( /\.\s*/, $verse_1->{text}, 2 );
        $text_parts[0] .= '.';

        if ( $setup->{opt}{print} ) {
            say ' ' x 8, '> ', $text_parts[0];
            say ' ' x 8, '> ', $text_parts[1];
        }

        $setup->{sth}{put_text}->run( $text_parts[0], $verse_1->{verse_id} );
        $setup->{sth}{put_text}->run( $text_parts[1], $verse_2->{verse_id} );
    }
}

sub merge_verses ( $simple_label, $setup ) {
    $setup //= setup();

    say 'Merge ', $simple_label, '...' if ( $setup->{opt}{print} );

    my ( $book, $chapter, $verse, $bibles ) = $simple_label =~ /^(.+?)\s+(\d+):(\d+)\s*(.*)/;
    for my $bible ( split( /\s+/, $bibles ) ) {
        say ' ' x 4, $bible, '...' if ( $setup->{opt}{print} );

        my $verse_1 = $setup->{sth}{get_verse}->run( $bible, $book, $chapter, $verse     )->first({});
        my $verse_2 = $setup->{sth}{get_verse}->run( $bible, $book, $chapter, $verse + 1 )->first({});

        next unless $verse_2;

        if ( $setup->{opt}{print} ) {
            say ' ' x 8, '> ', $verse_1->{text};
            say ' ' x 8, '> ', $verse_2->{text};
        }

        $setup->{sth}{put_text}->run(
            join( ' ', $verse_1->{text}, $verse_2->{text} ),
            $verse_1->{verse_id},
        );
        $setup->{sth}{delete_verse}->run( $verse_2->{verse_id} );
    }
}

=head1 NAME

integrate_bibles.pl - Integrates translation differences as per the docs

=head1 SYNOPSIS

    integrate_bibles.pl OPTIONS
        -p, --print
        -s, --save
        -f, --file  FILE  # docs file; defaults: "translation_integration.md"
        -h, --help
        -m, --man

=head1 DESCRIPTION

This program will integrate translation differences as per the documentation
covering this. (In fact, it uses part of the documentation as instruction
source.)

=head2 -p, --print

Print what is or would be changed Any line ending in "..." indicates a
section/block/set of changes, not changes themselves.

=head2 -s, --save

Save changes to the database.

=head2 -f, --file

The documentation file to read delete (not included) source instructions from.
Defaults to "translation_integration.md".

=cut
