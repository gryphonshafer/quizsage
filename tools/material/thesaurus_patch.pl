#!/usr/bin/env perl
use exact -cli, -conf;
use Mojo::JSON 'encode_json';
use Omniframe;
use Omniframe::Util::File 'opath';
use YAML::XS 'Load';

my $opt = options('input|i=s');
my $input;
try {
    $opt->{input} = opath( $opt->{input} // 'config/thesaurus_patch.yaml' );
    $input = Load( $opt->{input}->slurp );
}
catch ($e) {
    pod2usage( deat $e );
}

die "All patches in the input must have a text value and not both meanings and target values.\n" if ( grep {
    not length( $_->{text} ) or
    length( $_->{text} ) and $_->{meanings} and $_->{target}
} @$input );

my $dq = Omniframe->with_roles('+Database')->new->dq('material');

my $redirect_id = $dq->prepare_cached('SELECT word_id FROM word WHERE text = ?');
my $delete_word = $dq->prepare_cached('DELETE FROM word WHERE text = ?');
my $patch_word  = $dq->prepare_cached(q{
    INSERT INTO word ( redirect_id, meanings, text )
    VALUES ( ?, ?, ? )
    ON CONFLICT (text) DO
    UPDATE SET redirect_id = ?, meanings = ? WHERE text = ?
});

$dq->begin_work;

for my $patch (@$input) {
    if ( not $patch->{target} and not $patch->{meanings} ) {
        $delete_word->run( $patch->{text} );
    }
    else {
        $patch->{meanings} = encode_json( $patch->{meanings} ) if ( defined $patch->{meanings} );
        if ( defined $patch->{target} ) {
            $patch->{target} = $redirect_id->run( $patch->{target} )->value;
            die "Unable to locate target of $patch->{text}\n" unless ( $patch->{target} );
        }

        $patch_word->run(
            (
                $patch->{target},
                $patch->{meanings},
                $patch->{text},
            ) x 2,
        );
    }
}

$dq->commit;

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
