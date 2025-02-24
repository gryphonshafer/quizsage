#!/usr/bin/env perl
use exact -cli, -conf;
use Omniframe::Util::File 'opath';
use QuizSage::Model::Flag;

my $opt = options('input|i=s');
QuizSage::Model::Flag->new->thesaurus_patch( opath( $opt->{input} // 'config/thesaurus_patch.yaml' ) );

=head1 NAME

thesaurus_patch.pl - Patch the thesaurus contained in a material SQLite database

=head1 SYNOPSIS

    thesaurus_patch.pl OPTIONS
        -i, --input YAML_INPUT_FILE  # default: config/thesaurus_patch.yaml
        -h, --help
        -m, --man

=head1 DESCRIPTION

This program will patch the thesaurus contained in a material SQLite database.
By default, the program will look at the "~/config/thesaurus_patch.yaml" file
for input. The input is expected to be YAML and be an array of hashs. Each hash
should describe the end-state of a given word.

A regular, full entry will have C<text> (the word) and C<meanings> (a data
structure representing the synonyms of each meaning of the word):

    - text: see
      meanings:
        - word: perceive with eyes
          type: verb
          synonyms:
            - verity: 3
              words:
                  - look
                  - notice
                  - view
            - verity: 2
              words:
                  - mark
                  - note
                  - stare
            - verity: 1
              words:
                  - be apprised of
                  - pay attention to
                  - take notice
        - word: appreciate, comprehen
          type: verb
          synonyms:
            - verity: 3
              words:
                  - catch
                  - determine
                  - discover
              - verity: 2
              words:
                  - grasp
                  - imagine
                  - investigate
              - verity: 1
              words:
                  - get the drift
                  - get the hang of
                  - make out

For words that should just redirect to other words, use a C<target>:

    - text: saw
      target: see

To ensure a word does not exist in the thesaurus, define only the word:

    - text: Gryphon

Note that it's entirely reasonable (and recommended) to setup 2 entries for a
word that should be capicalized:

    - text: Christ
      meanings:
        - word: Jesus Christ
          type: noun
          synonyms:
            - verity: 1
              words:
                  - Emmanuel
                  - Good Shepherd
                  - Jesus
                  - King of Kings
                  - Lamb of God
                  - Light of the World
                  - lord
                  - Lord of Lords
                  - messiah
                  - Prince of Peace
                  - prophet
                  - redeemer
                  - savior
                  - Son of Man
    - text: christ
      target: Christ
