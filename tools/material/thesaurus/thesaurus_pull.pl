#!/usr/bin/env perl
use exact -cli, -conf;
use QuizSage::Model::Flag;
use Mojo::JSON 'from_json';
use YAML::XS 'Dump';

my $opt = options('input|i=s');
pod2usage unless $opt->{input};

my ( $text, $meanings ) = QuizSage::Model::Flag->new->dq('material')->sql( q{
    SELECT text, meanings FROM word WHERE
        redirect_id IS NULL AND text = ? OR
        word_id IN ( SELECT redirect_id FROM word WHERE redirect_id IS NOT NULL AND text = ? )
} )->run( ( $opt->{input} ) x 2 )->value;

unless ( $text and $meanings ) {
    warn 'Not found: ', $opt->{input}, "\n";
}
else {
    say Dump( [ { text => $text, meanings => from_json($meanings) } ] );
}

=head1 NAME

thesaurus_pull.pl - Pull thesaurus YAML for text input from the material database

=head1 SYNOPSIS

    thesaurus_pull.pl OPTIONS
        -i, --input TEXT
        -h, --help
        -m, --man

=head1 DESCRIPTION

This program will pull thesaurus YAML for text input from the material database.
