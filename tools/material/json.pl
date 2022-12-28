#!/usr/bin/env perl
use exact -cli, -conf;
use QuizSage::Util::Material 'json';

my $opt = options( qw{ label|l=s force|f } );

try {
    my $result = json( $opt->{label}, $opt->{force} );
    say
        ' Label: "', $result->{label}, '"', "\n",
        'Output: ', $result->{output};
}
catch ($error) {

die $error;

    $error =~ s/\sat\s\S+\sline\s\d+\.\s*$//g;
    pod2usage($error);
}

=head1 NAME

json.pl - Build JSON file of materials from material SQLite database

=head1 SYNOPSIS

    json.pl OPTIONS
        -l, --label REFERENCE_BLOCKS_AND_TRANSLATION_LABEL
        -f, --force
        -h, --help
        -m, --man

=head1 DESCRIPTION

This program will build JSON file of materials from material SQLite database,
unless that file already exits.

=head2 -l, --label

A string representing the reference range blocks, weights, and translations for
the expected output. For example:

    Romans 1-4; James (1) Romans 5-8 (1) ESV NASB NIV

A reference range block will contain a set of reference ranges followed by an
optional weight in parentheses. The list of translations will be at the end.

=head2 -f, --force

If set, this will create the output file even if it already exists.

=head1 JSON DATA STRUCTURE

The JSON data structure should look like this:

    label  : "Romans 1-4; James (1) Romans 5-8 (1) ESV NASB NIV",
    bibles : [ "NIV", "ESV", "NASB" ],
    blocks : [
        {
            range   : "Romans 1-4; James",
            weight  : 50,
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
            weight  : 50,
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
