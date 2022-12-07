#!/usr/bin/env perl
use exact -cli, -conf;
use Mojo::JSON qw( encode_json decode_json );
use Mojo::UserAgent;
use Omniframe;

my $opt = options( qw{ sleep|s=i estimate|e } );
$opt->{sleep} //= 4;

my $dq        = Omniframe->with_roles('+Database')->new->dq('material');
my $ua        = Mojo::UserAgent->new( max_redirects => 3 );
my $relevance = {
    'css-1kg1yv8 eh475bn0' => 1,
    'css-1gyuw4i eh475bn0' => 2,
    'css-1n6g4vv eh475bn0' => 3,
};

my %words     = map { map { $_ => 1 } split(/\s/) } $dq->sql('SELECT string FROM verse')->run->column;
my @words_pre = @{ $dq->sql('SELECT text FROM word')->run->column };
my @words_to  = grep {
    my $word = $_;
    not grep { $word eq $_ } @words_pre;
} keys %words;

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

my $insert_word    = $dq->prepare('INSERT INTO word (text) VALUES (?)');
my $select_word_id = $dq->prepare('SELECT word_id FROM word WHERE text = ?');

for ( my $i = 0; $i < @words_to; $i++ ) {
    my $word = $words_to[$i];
    my $dom  = $ua->get( 'https://www.thesaurus.com/browse/' . $word )->result->dom;

    $dq->begin_work;

    $insert_word->bind_param( 1, $word, 12 );
    $insert_word->execute;
    my $word_id = $insert_word->last_insert_id;

    if ( $dom->at('div#headword') ) {
        my $target_word = $dom->at('h1')->text;
        if ( $word ne $target_word ) { # word results in a redirect
            $select_word_id->bind_param( 1, $target_word, 12 );
            $select_word_id->execute;
            my ($target_word_id) = $select_word_id->fetchrow_array;

            unless ($target_word_id) {
                $insert_word->bind_param( 1, $target_word, 12 );
                $insert_word->execute;
                $target_word_id = $insert_word->last_insert_id;
                @words_to = grep { $_ ne $target_word } @words_to;
            }

            $dq->sql('UPDATE word SET redirect_id = ? WHERE word_id = ?')->run( $target_word_id, $word_id );
            $word_id = $target_word_id;
        }

        my $headwords = $dom->find('div#headword li a')->map( sub { +{
            meaning => $_->at('strong')->text,
            type    => $_->at('em')->text,
        } } )->to_array;

        my $meanings = $dom
            ->find('div#meanings ul, div#meanings ~ ul')
            ->head( scalar @$headwords )
            ->map( sub {
                my $meaning = shift @$headwords;
                $meaning->{synonyms} = $_->find('a')->map( sub {
                    ( my $word = $_->text ) =~ s/(^\s+|\s+$)//g;
                    +{
                        word      => $word,
                        relevance => $relevance->{ $_->attr('class') },
                    };
                } )->to_array;
                $meaning;
            } )->to_array;

        for (@$meanings) {
            $_->{word} = delete $_->{meaning};

            my $by_verity;
            push( @{ $by_verity->{ $_->{relevance} } }, $_->{word} ) for ( @{ $_->{synonyms} } );

            $_->{synonyms} = [
                map { +{
                    verity => $_,
                    words  => $by_verity->{$_},
                } } sort { $a <=> $b } keys %$by_verity
            ];
        }

        $dq->sql('UPDATE word SET meanings = ? WHERE word_id = ?')->run( encode_json($meanings), $word_id );
    }

    $dq->commit;

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

    sleep $opt->{sleep};
}

=head1 NAME

thesaurus.pl - Get synonyms and other data and save it a material SQLite database

=head1 SYNOPSIS

    thesaurus.pl OPTIONS
        -s, --sleep SECONDS  # default: 4
        -e, --estimate
        -h, --help
        -m, --man

=head1 DESCRIPTION

This program will get synonyms and other data and save it a material SQLite
database.

=head2 -s, --sleep

Integer of number of seconds to sleep between chapter pulls. Defaults to 4.

=head2 -e, --estimate

Estimates the time required to complete, but won't actually run.
