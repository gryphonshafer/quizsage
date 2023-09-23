#!/usr/bin/env perl
use exact -cli, -conf;
use QuizSage::Util::Material qw( canonicalize_label descriptionize_label );

my $opt = options( qw{ label|l=s force|f } );

# try {
    my $result = descriptionize_label( $opt->{label} );
    use DDP;
    p $result;

    # my $result = material_json( $opt->{label}, $opt->{force} );
    # say
    #     ' Label: "', $result->{label}, '"', "\n",
    #     'Output: ', $result->{output};
# }
# catch ($error) {
#     $error =~ s/\sat\s\S+\sline\s\d+\.\s*$//g;
#     pod2usage($error);
# }

=head1 NAME

json_from_db.pl - Build JSON file of materials from material SQLite database

=head1 SYNOPSIS

    json_from_db.pl OPTIONS
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

    Romans 1-4; James (1) Romans 5-8 (1) ESV NASB* NASB1995 NIV

A reference range block will contain a set of reference ranges followed by an
optional weight in parentheses. The list of translations will be at the end.

=head2 -f, --force

If set, this will create the output file even if it already exists.
