package QuizSage::Util::Material;

use exact -conf, -fun;
use Digest;
use File::Path 'make_path';
use Mojo::File 'path';
use Mojo::JSON qw( encode_json decode_json );
use QuizSage::Model::Label;

exact->exportable( qw{ text2words material_json } );

sub text2words ($text) {
    $text =~ s/(^|\W)'(\w.*?)'(\W|$)/$1$2$3/g; # remove single-quotes from around words/phrases

    $text =~ s/[,:\-]+$//g;            # remove commas, colons, and dashes at end of lines
    $text =~ s/,'//g;                  # remove commas followed by single-quote
    $text =~ s/[,:](?=\D)//g;          # remove commas and colons except for "1,234" and "3:00"
    $text =~ s/[^A-Za-z0-9'\-,:]/ /gi; # remove all but "usable" characters
    $text =~ s/(\d)\-(\d)/$1 $2/g;     # convert dashes between numbers into spaces
    $text =~ s/(?<!\w)'/ /g;           # remove single-quote following a non-word character
    $text =~ s/(\w)'(?=\W|$)/$1/g;     # remove single-quote following a word character prior to a non-word
    $text =~ s/\-{2,}/ /g;             # convert double-dashes into spaces
    $text =~ s/\s+/ /g;                # compact multi-spaces
    $text =~ s/(?:^\s|\s$)//g;         # trim spacing

    return [ split( /\s/, lc($text) ) ];
}

fun material_json (
    :$description = undef, # assumed to be canonical
    :$label       = undef, # not required to be canonical
    :$user        = undef, # user ID from application database
    :$force       = 0,
) {
    croak('Must provide either label or description (and not both)')
        if ( not $description and not $label or $description and $label );

    my $model_label = QuizSage::Model::Label->new( user_id => $user );
    $description    = $model_label->descriptionize($label) if ($label);

    my $json_file = path(
        join( '/',
            conf->get( qw{ config_app root_dir } ),
            conf->get( qw{ material json } ),
            substr( Digest->new('SHA-256')->add($description)->hexdigest, 0, 16 ) . '.json',
        )
    );

    my $return = {
        description => $description,
        json_file   => $json_file->to_string,
    };

    return $return if ( not $force and -f $json_file );

    # setup data structure
    my $data = $model_label->parse($description);
    $data->{description} = $description;
    $_->{range} = $_->{range}[0] for ( $data->{ranges}->@* );

    croak('Must supply at least 1 valid reference range') unless ( $data->{ranges}->@* );
    croak('Must have least 1 primary supported Bible translation by canonical acronym')
        unless ( $data->{bibles} and $data->{bibles}{primary} and $data->{bibles}{primary}->@* );

    my $dq_material = $model_label->dq('material');

    # add verse content
    my @bibles = sort $data->{bibles}{primary}->@*, $data->{bibles}{auxiliary}->@*;
    my %words;
    for my $range ( $data->{ranges}->@* ) {
        for my $ref ( $model_label->bible_ref->clear->simplify(0)->in( $range->{range} )->as_verses->@* ) {
            $ref =~ /^(?<book>.+)\s+(?<chapter>\d+):(?<verse>\d+)$/;
            my $material = $dq_material->get(
                [
                    [ [ 'verse' => 'v' ] ],
                    [ { 'bible' => 't' }, 'bible_id' ],
                    [ { 'book'  => 'b' }, 'book_id'  ],
                ],
                [ [ 't.acronym', 'bible' ], [ 'b.name', 'book' ], 'v.chapter', 'v.verse', 'v.text' ],
                {
                    't.acronym' => \@bibles,
                    'b.name'    => $+{book},
                    'v.chapter' => $+{chapter},
                    'v.verse'   => $+{verse},
                },
            )->run->all({});
            next unless ( @$material == @bibles );
            for my $verse (@$material) {
                $verse->{words} = text2words( $verse->{text} );
                $words{$_} = 1 for ( $verse->{words}->@* );
                push( @{ $range->{content}{ delete $verse->{bible} } }, $verse );
            }
        }
    }

    # add thesaurus
    my $thesaurus = $dq_material->sql(q{
        SELECT
            w.text AS text,
            r.text AS redirected_to,
            COALESCE( w.meanings, r.meanings ) AS meanings
        FROM word AS w
        LEFT JOIN word AS r ON w.redirect_id = r.word_id
        WHERE w.text = ?
    });
    for my $word ( sort keys %words ) {
        my $synonym = $thesaurus->run($word)->first({});
        next unless ( $synonym->{meanings} );
        $data->{thesaurus}{ $synonym->{redirected_to} // $word } = decode_json( $synonym->{meanings} );
        $data->{thesaurus}{$word} = $synonym->{redirected_to} if ( $synonym->{redirected_to} );
    }

    # save data to JSON file and return path/name
    make_path( $json_file->dirname ) unless ( -d $json_file->dirname );
    $json_file->spew( encode_json($data) );

    return $return;
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
