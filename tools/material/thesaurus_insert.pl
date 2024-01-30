#!/usr/bin/env perl
use exact -cli, -conf;
use Mojo::JSON 'encode_json';
use Mojo::UserAgent;
use Mojo::Util 'trim';
use Omniframe;
use QuizSage::Util::Material 'text2words';

my $opt = options( qw{ sleep|s=i estimate|e } );
$opt->{sleep} //= 4;

my $dq = Omniframe->with_roles('+Database')->new->dq('material');
my $ua = Mojo::UserAgent->new( max_redirects => 3 );

say 'Determining words to thesaurusize...';
my %words =
    map { map { $_ => length $_ } @{ text2words($_) } }
    $dq->sql('SELECT text FROM verse')->run->column;
my @words_pre = @{ $dq->sql('SELECT text FROM word')->run->column };
my @words_to  =
    grep {
        my $word = $_;
        not grep { $word eq $_ } @words_pre;
    }
    sort {
        $words{$a} <=> $words{$b} or
        $a cmp $b
    }
    keys %words;

my ( $start, $total ) = ( time, scalar(@words_to) );

if ( $opt->{estimate} ) {
    my $seconds_remaining = $total * $opt->{sleep};

    my $hours   = int( $seconds_remaining / 60 / 60 );
    my $minutes = int( ( $seconds_remaining - $hours * 60 * 60 ) / 60 );
    my $seconds = ( $seconds_remaining - $hours * 60 * 60 - $minutes * 60 );

    printf " Words to get: %9s\nSeconds sleep: %9s\nTime estimate: %3d:%02d:%02d\n",
        $total,
        $opt->{sleep},
        $hours,
        $minutes,
        $seconds;

    exit;
}

my $insert_text          = $dq->prepare_cached('INSERT INTO word (text) VALUES (?)');
my $insert_text_meanings = $dq->prepare_cached('INSERT INTO word ( text, meanings ) VALUES ( ?, ? )');
my $select_word_id       = $dq->prepare_cached('SELECT word_id FROM word WHERE text = ?');
my $insert_id_text       = $dq->prepare_cached('INSERT INTO word ( redirect_id, text ) VALUES ( ?, ? )');

say 'Beginning thesaurusization...';
for ( my $i = 0; $i < @words_to; $i++ ) {
    my $word = $words_to[$i];
    ( my $term = $word ) =~ s/'s?$//;

    my $dom;
    my $try_dom = sub ($term) {
        return unless $term;
        sleep $opt->{sleep};

        my ( $_dom, $attempts );
        while ( not $_dom ) {
            say "DOM attempt $attempts..." if ( ++$attempts > 1 );

            try {
                $_dom = $ua->get( 'https://www.thesaurus.com/browse/' . $term )->result->dom;
            }
            catch ($e) {
                die $e unless ( $e =~ /Inactivity timeout/ );
            }
        }

        die "Unable to find H1 for $word ($term)" unless ( $_dom->at('h1') );
        return undef if ( $_dom->at('h1')->text =~ /\b0 results\b/ );
        return $dom = $_dom;
    };

    $try_dom->($term);
    if ( not $dom ) {
        if ( $term =~ s/ing$// or $term =~ s/ies$/y/ or $term =~ s/(?<!e)s$// ) {
            $try_dom->($term);
            $try_dom->($term) if ( not $dom and $term =~ s/ing$// );
        }
        elsif ( $term =~ s/ed$// ) {
            $try_dom->($term);
        }
        elsif ( $term =~ /es$/ ) {
            $term =~ s/s$//;
            $try_dom->($term);
            $try_dom->($term) if ( not $dom and $term =~ s/e$// );
        }
    }

    if ( not $dom ) {
        $insert_text->run($word);
    }
    else {
        my $text = $dom->at('h1')->text;

        my $meanings = $dom->find(
            'section[data-type="synonym-antonym-module"] ' .
            'div[data-type="synonym-and-antonym-card"]'
        )->map( sub ($card) {
            my $card_head = $card->at('p');
            +{
                word     => trim( $card_head->at('strong')->text ),
                type     => trim( $card_head->text ),
                synonyms => $card->find('div > div > div > p')->map( sub ($synonym) { +{
                    words => [
                        grep {
                            my $match = lc $_;
                            not grep { $_ eq $match } qw( hir sie ve ver vis xe xem xyr ze zie zir );
                        }
                        $synonym->parent->find('li a')->map('text')->to_array->@*
                    ],
                    verity =>
                        ( $synonym->text =~ /Strongest/ ) ? 3 :
                        ( $synonym->text =~ /Strong/    ) ? 2 :
                        ( $synonym->text =~ /Weak/      ) ? 1 : 0,
                } } )->to_array,
            };
        } )->to_array;

        $dq->begin_work;

        try {
            $insert_text_meanings->run( $text, encode_json $meanings );
        }
        catch ($e) {
            die $e unless ( $e =~ /DBD::SQLite::st execute failed: UNIQUE constraint failed/ );
        }

        if ( $word ne $text ) {
            my $id = $select_word_id->run($text)->value;
            $insert_id_text->run( $id, $word );
        }

        $dq->commit;
    }

    my $items_completed   = $i + 1;
    my $seconds_remaining = int( ( time - $start ) / $items_completed * ( $total - $items_completed ) );

    my $hours   = int( $seconds_remaining / 60 / 60 );
    my $minutes = int( ( $seconds_remaining - $hours * 60 * 60 ) / 60 );
    my $seconds = ( $seconds_remaining - $hours * 60 * 60 - $minutes * 60 );

    printf "%5d of %5d %3d%% %3d:%02d:%02d => %s\n",
        $items_completed,
        $total,
        int( $items_completed / $total * 100 ),
        $hours,
        $minutes,
        $seconds,
        $word;
}

=head1 NAME

thesaurus_insert.pl - Get and insert synonyms and other data into a material SQLite database

=head1 SYNOPSIS

    thesaurus_insert.pl OPTIONS
        -s, --sleep SECONDS  # default: 4
        -e, --estimate
        -h, --help
        -m, --man

=head1 DESCRIPTION

This program will get and insert synonyms and other data into a material SQLite
database.

=head2 -s, --sleep

Integer of number of seconds to sleep between chapter pulls. Defaults to 4.

=head2 -e, --estimate

Estimates the time required to complete, but won't actually run.
