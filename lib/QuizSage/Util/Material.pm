package QuizSage::Util::Material;

use exact -conf;
use Bible::Reference;
use Digest;
use File::Path 'make_path';
use Math::Prime::Util 'divisors';
use Mojo::File 'path';
use Mojo::JSON qw( encode_json decode_json );
use Omniframe;

exact->exportable( qw{ canonicalize_label descriptionize_label data_structure material_json text2words } );

my $ref = Bible::Reference->new(
    acronyms   => 0,
    sorting    => 1,
    add_detail => 1,
);

my $db          = Omniframe->with_roles('+Database')->new;
my $dq_material = $db->dq('material');
my $dq_app      = $db->dq('app');

my $material = $dq_material->sql(q{
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

my $thesaurus = $dq_material->sql(q{
    SELECT
        w.text AS text,
        r.text AS redirected_to,
        COALESCE( w.meanings, r.meanings ) AS meanings
    FROM word AS w
    LEFT JOIN word AS r ON w.redirect_id = r.word_id
    WHERE w.text = ?
});

my $acronyms = $dq_material->sql('SELECT acronym FROM bible ORDER BY LENGTH(acronym) DESC, acronym');

#-------------------------------------------------------------------------------------------------------------

sub data_structure($label) {
    my $data;

    # add bibles

    my $bible_re = '\b((?:' . join( '|', $acronyms->run->column->@* ) . ')(?:(?:\s*\*+)|\b))';

    while ( $label =~ s/$bible_re//i ) {
        my $bible = uc $1;
        $data->{bibles}{ ( $bible =~ s/\s*\*+// ) ? 'auxiliary' : 'primary' }{$bible} = 1;
    }

    $data->{bibles}{primary}   = [ sort keys %{ $data->{bibles}{primary} } ];
    $data->{bibles}{auxiliary} = [
        sort
        grep {
            my $bible = $_;
            not grep { $_ eq $bible } $data->{bibles}{primary}->@*;
        }
        keys %{ $data->{bibles}{auxiliary} }
    ];

    croak('Must supply at least 1 supported Bible translation by canonical acronym')
        unless ( $data->{bibles}{primary}->@* );

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
                content => {
                    map { $_ => [@$verses] }
                    sort $data->{bibles}{primary}->@*, $data->{bibles}{auxiliary}->@*
                },
            };
        } split( /(?<=\([^\)]{,64})\)/, $label )
    ];

    croak('Must supply at least 1 valid reference range') unless ( $data->{blocks}->@* );

    # lowest-common-denominator-ify weights
    my @weights = map { $_->{weight} } $data->{blocks}->@*;
    my %factors;
    $factors{$_}++ for ( map { divisors($_) } @weights );
    my ($largest_common_factor) = sort { $b <=> $a } grep { $factors{$_} == @weights } keys %factors;
    @weights = map { $_ / $largest_common_factor } @weights;
    $_->{weight} = shift @weights for ( $data->{blocks}->@* );

    # add canonicalized label
    $data->{label} = join( ' ',
        (
            map {
                $_->{range} . ( ( $data->{blocks}->@* > 1 ) ? ' (' . $_->{weight} . ')' : '' )
            } $data->{blocks}->@*
        ),
        ( sort $data->{bibles}{primary}->@*, map { $_ . '*' } $data->{bibles}{auxiliary}->@* ),
    );

    $data->{hash} = Digest->new('SHA-256')->add( $data->{label} )->hexdigest;

    delete $data->{bibles}{auxiliary} unless ( $data->{bibles}{auxiliary}->@* );
    return $data;
}

sub material_json ( $label, $force = 0 ) {
    my $data   = data_structure($label);
    my $output = path(
        join( '/', conf->get( qw{ material json } ), substr( $data->{hash}, 0, 16 ) . '.json' )
    );

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
    $output->spew( encode_json($data) );

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
    s/(?<!\w)'/ /g;                   # remove single-quote following a non-word character
    s/(\w)'(?=\W|$)/$1/g;             # remove single-quote following a word character prior to a non-word
    s/\-{2,}/ /g;                     # convert double-dashes into spaces
    s/\s+/ /g;                        # compact multi-spaces
    s/(?:^\s|\s$)//g;                 # trim spacing

    return [ split( /\s/, lc($_) ) ];
}

1;

=head1 NAME

QuizSage::Util::Material

=head1 SYNOPSIS

    use QuizSage::Util::Material qw( material_json text2words );

    my @words = text2words(
        q{Jesus asked, "What's (the meaning of) this: 'I and my Father are one.'"}
    )->@*;

    my %results = material_json( 'Acts 1-20 NIV', 'force' )->%*;

=head1 DESCRIPTION

This package provides exportable utility functions.

=head1 FUNCTIONS

=head2 material_json

This function accepts a material label string and will build a JSON material
data file using data from the material database. A material label represents
the reference range blocks, weights, and translations for the expected output.
For example:

    Romans 1-4; James (1) Romans 5-8 (1) ESV NASB* NASB1995 NIV

The function accepts an optional second value, an boolean value, to indicate if
an existing JSON file should be rebuilt. (Default is false.)

    my %results = material_json( 'Acts 1-20 NIV', 'force' )->%*;

The function returns a hashref with a C<label> and C<output> keys. The "label"
will be the canonicalized material label, and the "output" is the file that was
created or recreated.

sub =head2 canonicalize_label($label) {

Take a string input of a material label and return that label canonicalized.

=head3 JSON DATA STRUCTURE

The JSON data structure should look like this:

    label  : "Romans 1-4; James (1) Romans 5-8 (1) ESV NASB NIV",
    bibles : [ "NIV", "ESV", "NASB" ],
    blocks : [
        {
            range   : "Romans 1-4; James",
            weight  : 1,
            content : {
                NIV : [
                    {
                        book    : "Romans",
                        chapter : 1,
                        verse   : 1,
                        text    : "Paul, a servant of Christ Jesus, called to",
                        string  : "paul a servant of christ jesus called to",
                    },
                ],
                ESV  : [],
                NASB : [],
            },
        },
        {
            range   : "Romans 5-8",
            weight  : 1,
            content : {
                NIV  : [],
                ESV  : [],
                NASB : [],
            },
        },
    ],
    thesaurus : {
        called : [
            {
                type     : "adj.",
                word     : "named",
                synonyms : [
                    {
                        verity : 1,
                        words  : ["labeled"],
                    },
                    {
                        verity : 2,
                        words  : [ "christened", "termed" ],
                    },
                ],
            ],
        ],
        almighty : "the Almighty",
    }

=head2 text2words

This function accepts a string and will return an arrayref of lower-case words
from the string.

    my @words = text2words(
        q{Jesus asked, "What's (the meaning of) this: 'I and my Father are one.'"};
    )->@*;

=head2 aliases

Subroutine C<aliases>.

=head2 parse_label

Subroutine C<parse_label>.

=head2 canonicalize_label

Subroutine C<canonicalize_label>.

=head2 descriptionize_label

Subroutine C<descriptionize_label>.

=head2 data_structure

Subroutine C<data_structure>.
