package QuizSage::Util::Material;

use exact -conf;
use Bible::Reference;
use File::Path 'make_path';
use Math::Prime::Util 'divisors';
use Mojo::File 'path';
use Mojo::JSON qw( encode_json decode_json );
use Omniframe;

exact->exportable( qw{ json text2words } );

my $ref = Bible::Reference->new(
    acronyms   => 0,
    sorting    => 1,
    add_detail => 1,
);

my $dq = Omniframe->with_roles('+Database')->new->dq('material');

my $material = $dq->sql(q{
    SELECT
        b.name AS book,
        v.chapter,
        v.verse,
        v.text,
        v.string
    FROM verse AS v
    JOIN bible AS t USING (bible_id)
    JOIN book AS b USING (book_id)
    WHERE t.acronym = ? AND b.name = ? AND v.chapter = ? AND v.verse = ?
});

my $thesaurus = $dq->sql(q{
    SELECT
        w.text AS text,
        r.text AS redirected_to,
        COALESCE( w.meanings, r.meanings ) AS meanings
    FROM word AS w
    LEFT JOIN word AS r ON w.redirect_id = r.word_id
    WHERE w.text = ?
});

sub json ( $label, $force ) {
    my $data;

    # add bibles
    my $bible_re = '\b(' . join( '|', @{ $dq->sql('SELECT acronym FROM bible')->run->column } ) . ')\b';
    $data->{bibles}{ uc $1 } = 1 while ( $label =~ s/$bible_re//i );
    $data->{bibles} = [ sort keys %{ $data->{bibles} } ];
    croak('Must supply at least 1 supported Bible translation by acronym') unless ( @{ $data->{bibles} } );

    # add range/weight blocks
    my $last_weight;
    $data->{blocks} = [
        grep { $_->{range} } map {
            s/\(([^\)]+)$//;
            ( my $weight = $1 || '' ) =~ s/[^\d]+//g;;
            $weight      = 0 + ( $weight || $last_weight || 1 );
            $last_weight = $weight;

            my $verses = $ref->clear->simplify(0)->in($_)->as_verses;

            +{
                range   => $ref->clear->simplify(1)->in($_)->refs,
                weight  => 0 + ( $weight || 1 ),
                content => { map { $_ => [@$verses] } @{ $data->{bibles} } },
            };
        } split( /(?<=\([^\)]{,64})\)/, $label )
    ];
    croak('Must supply at least 1 valid reference range') unless ( @{ $data->{blocks} } );

    # lcd weights
    my @weights = map { $_->{weight} } @{ $data->{blocks} };
    my %factors;
    $factors{$_}++ for ( map { divisors($_) } @weights );
    my ($largest_common_factor) = sort { $b <=> $a } grep { $factors{$_} == @weights } keys %factors;
    @weights = map { $_ / $largest_common_factor } @weights;
    $_->{weight} = shift @weights for ( @{ $data->{blocks} } );

    # add canonicalized label
    $data->{label} = join( ' ',
        (
            map {
                $_->{range} . ( ( @{ $data->{blocks} } > 1 ) ? ' (' . $_->{weight} . ')' : '' )
            } @{ $data->{blocks} }
        ),
        ( @{ $data->{bibles} } ),
    );

    # return JSON file path/name if it already exists
    ( my $filename = $data->{label} ) =~ tr/\(\);: /\{\}+%_/;
    my $output = path( join( '/', conf->get( qw{ material json } ), $filename . '.json' ) );
    return {
        label  => $data->{label},
        output => $output->to_string,
    } if ( not $force and -f $output );

    # add verse content
    my $verses_to_filter;
    for my $block ( @{ $data->{blocks} } ) {
        for my $bible ( keys %{ $block->{content} } ) {
            $block->{content}{$bible} = [ grep { defined } map {
                /^(?<book>.+)\s+(?<chapter>\d+):(?<verse>\d+)$/;
                my $verse = $material->run( $bible, $+{book}, $+{chapter}, $+{verse} )->first({});
                $verses_to_filter->{ join( '|', $+{book}, $+{chapter}, $+{verse} ) } = 1
                    unless ( $verse and $verse->{text} );
                $verse;
            } @{ $block->{content}{$bible} } ];
        }
    }
    my $words;
    for my $block ( @{ $data->{blocks} } ) {
        for my $bible ( keys %{ $block->{content} } ) {
            $block->{content}{$bible} = [ grep { defined } map {
                my $verse = $_;
                unless (
                    $verses_to_filter->{
                        join( '|', $verse->{book}, $verse->{chapter}, $verse->{verse} )
                    }
                ) {
                    $words->{$_} = 1 for ( split( /\s/, $verse->{string} ) );
                    $verse;
                }
                else {
                    undef;
                }
            } @{ $block->{content}{$bible} } ];
        }
    }

    # add thesaurus
    for my $word ( sort keys %$words ) {
        my $synonym = $thesaurus->run($word)->first({});
        next unless ( $synonym->{meanings} );
        $data->{thesaurus}{ $synonym->{redirected_to} // $word } = decode_json( $synonym->{meanings} );
        $data->{thesaurus}{$word} = $synonym->{redirected_to} if ( $synonym->{redirected_to} );
    }

    # save data to JSON file and return path/name
    make_path( $output->dirname ) unless ( -d $output->dirname );
    $output->spurt( encode_json($data) );

    return {
        label  => $data->{label},
        output => $output->to_string,
    };
}

sub text2words ($text) {
    $_ = $text;

    s/(^|\W)'(\w.*?)'(\W|$)/$1$2$3/g; # remove single-quotes from around words/phrases
    s/[,:\-]+$//g;                    # remove commas, colons, and dashes at end of lines
    s/,'//g;                          # remove commas followed by single-quote
    s/[,:](?=\D)//g;                  # remove commas and colons except for "1,234" and "3:00"
    s/[^A-Za-z0-9'\-,:]/ /gi;         # remove all but "usable" characters
    s/(\d)\-(\d)/$1 $2/g;             # convert dashes between numbers into spaces
    s/(?<!\w)'/ /g;                   # remove sigle-quote following a non-word character
    s/(\w)'(?=\W|$)/$1/g;             # remove sigle-quote following a word character prior to a non-word
    s/\-{2,}/ /g;                     # convert double-dashes into spaces
    s/\s+/ /g;                        # compact multi-spaces
    s/(?:^\s|\s$)//g;                 # trim spacing

    return [ split( /\s/, lc($_) ) ];
}

1;
