#!/usr/bin/env perl
use exact -cli, -conf;
use Omniframe;
use Mojo::JSON 'decode_json';

my $opt = options('buffer|b=i');
$opt->{buffer} //= 25_000;

my $dq = Omniframe->with_roles('+Database')->new->dq('material');

$dq->begin_work;
$dq->do('DELETE FROM reverse');

my @buffer;
sub write_buffer ( $size = 0 ) {
    if ( @buffer and @buffer > $size ) {
        $dq->do(
            'INSERT OR IGNORE INTO reverse ( word_id, synonym, verity ) VALUES ' .
            join( ',', map { '(' . join( ',', @$_ ) . ')' } @buffer )
        );
        @buffer = ();
    }
}

$dq->sql('SELECT word_id, meanings FROM word WHERE meanings IS NOT NULL')->run->each( sub ($row) {
    my $data     = $row->data;
    my $meanings = decode_json( $data->{meanings} );

    for my $synonym ( map { $_->{synonyms}->@* } $meanings->@* ) {
        for my $word ( $synonym->{words}->@* ) {
            state $count = 1;
            printf "%7d %s\n", $count++, $word;
            push( @buffer, [ $data->{word_id}, $dq->quote($word), $synonym->{verity} ] );
        }
    }

    write_buffer( $opt->{buffer} );
} );

write_buffer;
$dq->commit;

=head1 NAME

thesaurus_reverse.pl - Builds/rebuilds the thesaurus reverse lookup table

=head1 SYNOPSIS

    thesaurus_reverse.pl OPTIONS
        -b, --buffer INTEGER # buffer size before database insert; default 25k
        -h, --help
        -m, --man

=head1 DESCRIPTION

This program will build (or rebuild) the thesaurus reverse lookup table in a
material SQLite database.
