#!/usr/bin/env perl
use exact -cli, -conf;
use QuizSage::Util::Material 'material_json';

my $opt = options( qw{ description|d=s label|l=s user|u=i force|f } );

try {
    my $result = material_json(%$opt);
    say
        '  JSON File: ',  $result->{json_file}, "\n",
        'Description: "', $result->{description}, '"';
}
catch ($error) {
    $error =~ s/\sat\s\S+\sline\s\d+\.\s*$//g;
    pod2usage($error);
}

=head1 NAME

json_build.pl - Build JSON file of materials from material SQLite database

=head1 SYNOPSIS

    json_build.pl OPTIONS
        -d, --description CANONICALIZED_MATERIAL_DESCRIPTION
        -l, --label       REFERENCE_BLOCKS_AND_TRANSLATION_LABEL
        -u, --user        USER_ID
        -f, --force
        -h, --help
        -m, --man

=head1 DESCRIPTION

This program will build JSON file of materials from material SQLite database,
unless that file already exits.

=head2 -d, --description

A string containing a canonicalized material description.
See L<QuizSage::Model::Label>.

=head2 -l, --label

A string representing the reference range blocks, weights, and translations for
the expected output, which may be a label and/or contain alias labels.
See L<QuizSage::Model::Label>. For example:

    Romans 1-4; James (1) Romans 5-8 (1) ESV NASB* NASB1995 NIV

A reference range block will contain a set of reference ranges followed by an
optional weight in parentheses. The list of translations will be at the end.

The string will be internally descriptionalized via L<QuizSage::Model::Label>.

=head2 -u, --user

User ID used to select private aliases when a label is provided for
descriptionalization. If not provided, only public aliases will be used.

=head2 -f, --force

If set, this will create the output file even if it already exists.
