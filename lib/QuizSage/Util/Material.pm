package QuizSage::Util::Material;

use exact -conf, -fun;
use Digest;
use File::Path 'make_path';
use Mojo::File 'path';
use Mojo::JSON qw( to_json from_json );
use Omniframe::Class::Time;
use QuizSage::Model::Label;

exact->exportable( qw{ text2words material_json synonyms_of_term } );

sub text2words ( $text, $skip_lc = 0 ) {
    $text = lc $text unless ($skip_lc);

    $text =~ s/(^|\W)'(\w.*?)'(\W|$)/$1$2$3/g; # rm single-quotes from around words/phrases
    $text =~ s/[,:\-]+$//g;                    # rm commas, colons, and dashes at end of lines
    $text =~ s/,'//g;                          # rm commas followed by single-quote
    $text =~ s/[,:](?=\D)//g;                  # rm commas/colons except for "1,234" and "3:00"
    $text =~ s/[^a-z0-9'\-,:]/ /gi;            # rm all but "usable" characters
    $text =~ s/(\d)\-(\d)/$1 $2/g;             # convert dashes between numbers into spaces
    $text =~ s/(?<!\w)'/ /g;                   # rm single-quote after a non-word character
    $text =~ s/(\w)'(?=\W|$)/$1/g;             # rm single-quote after a word char prior to a non-word
    $text =~ s/\-{2,}/ /g;                     # convert double-dashes into spaces
    $text =~ s/\s+/ /g;                        # compact multi-spaces
    $text =~ s/(?:^\s|\s$)//g;                 # trim spacing

    return [ split( /\s/, $text ) ];
}

my $time = Omniframe::Class::Time->new;

fun material_json (
    :$label = undef, # not required to be canonical
    :$user  = undef, # user ID from application database
    :$force = 0,
) {
    my $now       = time;
    my $json_path = path( join( '/',
        conf->get( qw{ config_app root_dir } ),
        conf->get( qw{ material json location } ),
    ) );
    my $delete_if_before = $time->parse(
        conf->get( qw{ material json delete_if_before } )
    )->{datetime}->epoch;
    $json_path->list->grep( sub ($file) {
        $file->stat->atime < $delete_if_before
    } )->each('remove');
    # remove any material JSON files that haven't been accessed in the last N
    # days, where N is from config: material json atime_life
    my $atime_life = conf->get( qw{ material json atime_life } );
    $json_path->list->grep( sub ($file) {
        ( $now - $file->stat->atime ) / ( 60 * 60 * 24 ) > $atime_life
    } )->each('remove');

    croak('Must provide label') unless ($label);

    my $model_label            = QuizSage::Model::Label->new( user_id => $user );
    my $parse                  = $model_label->parse($label);
    my ( $description, $data ) = $model_label->descriptionate($parse);

    croak('Must supply at least 1 valid reference range') unless ( $data->{ranges} and $data->{ranges}->@* );
    croak('Must have least 1 primary supported canonical Bible acronym')
        unless ( $data->{bibles} and $data->{bibles}{primary} and $data->{bibles}{primary}->@* );

    $data->{canonical} = $model_label->format($parse);

    my $id        = substr( Digest->new('SHA-256')->add($description)->hexdigest, 0, 16 );
    my $json_file = $json_path->child( $id . '.json' );
    my $return    = {
        label       => $data->{canonical},
        description => $description,
        json_file   => $json_file,
        id          => $id,
    };

    return $return if ( not $force and -f $json_file );

    $data->{description} = $description;
    $data->{bibles}      = {
        map { $_->[0] => { type => ( ( $_->[1] ) ? 'auxiliary' : 'primary' ) } }
        sort { $a->[0] cmp $b->[0] }
        ( map { [ $_, 0 ] } $data->{bibles}{primary  }->@* ),
        ( map { [ $_, 1 ] } $data->{bibles}{auxiliary}->@* ),
    };
    $_->{verses} = $model_label->versify_refs( $_->{range} ) for ( $data->{ranges}->@* );

    my $dq_material = $model_label->dq('material');

    # add verse content
    my @bibles = sort keys $data->{bibles}->%*;
    my %words;
    for my $range ( $data->{ranges}->@* ) {
        for my $ref ( $range->{verses}->@* ) {
            next if (
                $data->{bibles}{ $bibles[0] }{content} and
                $data->{bibles}{ $bibles[0] }{content}{$ref}
            );

            $ref =~ /^(?<book>.+)\s+(?<chapter>\d+):(?<verse>\d+)$/;

            my $material = $dq_material->get(
                [
                    [ [ 'verse' => 'v' ] ],
                    [ { 'bible' => 't' }, 'bible_id' ],
                    [ { 'book'  => 'b' }, 'book_id'  ],
                ],
                [ [ 't.acronym', 'bible' ], 'v.text' ],
                {
                    't.acronym' => \@bibles,
                    'b.name'    => $+{book},
                    'v.chapter' => $+{chapter},
                    'v.verse'   => $+{verse},
                },
            )->run->all({});

            unless ( @$material == @bibles ) {
                $range->{verses} = [ grep { $_ ne $ref } $range->{verses}->@* ];
                next;
            }

            for my $verse (@$material) {
                $words{$_} = 1 for ( @{ text2words( $verse->{text} ) } );
                $data->{bibles}{ $verse->{bible} }{content}{$ref} = {
                    text => $verse->{text},
                };
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

        $synonym->{meanings} = [
            grep { $_->{synonyms}->@* }
            map {
                $_->{synonyms} = [
                    grep { $_->{words}->@* }
                    $_->{synonyms}->@*
                ];
                $_;
            }
            from_json( $synonym->{meanings} )->@*
        ];
        next unless ( $synonym->{meanings}->@* );

        $data->{thesaurus}{ $synonym->{redirected_to} // $word } = $synonym->{meanings};
        $data->{thesaurus}{$word} = $synonym->{redirected_to} if ( $synonym->{redirected_to} );
    }

    # save data to JSON file and return path/name
    make_path( $json_file->dirname ) unless ( -d $json_file->dirname );
    $json_file->spew( to_json($data), 'UTF-8' );

    return $return;
}

sub synonyms_of_term ( $term, $settings = {} ) {
    croak('Term must be provided') unless ( length $term );

    for (
        [ case_sensitive        => 0 ],
        [ skip_substring_search => 0 ],
        [ skip_term_splitting   => 0 ],
        [ minimum_verity        => 0 ],
        [ direct_lookup         => 1 ],
        [ reverse_lookup        => 1 ],
    ) {
        $settings->{ $_->[0] } = $_->[1] if ( not exists $settings->{ $_->[0] } );
    }
    $settings->{ignored_types} //= [ 'article', 'preposition' ];
    $settings->{special_types} //= ['pronoun'];

    my $matches;
    my @terms = ( $settings->{skip_term_splitting} ) ? $term : do {
        my @split = grep { /\w/ } split( /\s+/, $term );
        ( @split > 1 ) ? ( $term, @split ) : $term;
    };

    my $dq = QuizSage::Model::Label->new->dq('material');

    if ( $settings->{direct_lookup} ) {
        for my $match (
            map {
                $_->{lookup} = 'direct';
                $_;
            }
            $dq->get(
                'word',
                [ qw( word_id redirect_id text meanings ) ],
                {
                    -and => {
                        -or => {
                            redirect_id => { '!=', undef },
                            meanings    => { '!=', undef },
                        },
                        ( $settings->{case_sensitive} )
                            ? ( text =>
                                ( $settings->{skip_substring_search} )
                                    ? { -in   => \@terms }
                                    : { -glob => [ map { '*' . $_ . '*' } @terms ] }
                            )
                            : ( 'LOWER(text)' =>
                                ( $settings->{skip_substring_search} )
                                    ? { '='   => [ map { \[ 'LOWER(?)', $_             ] } @terms ] }
                                    : { -glob => [ map { \[ 'LOWER(?)', '*' . $_ . '*' ] } @terms ] }
                            )
                    },
                },
            )->run->all({})->@*
        ) {
            if ( $match->{redirect_id} ) {
                push( @$matches, $dq->get(
                    'word',
                    [ qw( word_id text meanings ) ],
                    { word_id => $match->{redirect_id} }
                )->run->first({}) ) if ( not grep { $_->{word_id} == $match->{redirect_id} } @$matches );
            }
            else {
                push( @$matches, $match );
            }
        }
    }

    push( @$matches,
        map {
            $_->{lookup} = 'reverse';
            $_;
        }
        $dq->get(
            'word',
            [ qw( text meanings ) ],
            {
                -and => [
                    word_id => { -not_in => [ map { $_->{word_id } } @$matches ] },
                    word_id => { -in     =>
                        scalar $dq->get(
                            'reverse',
                            [ \q{ DISTINCT word_id } ],
                            {
                                ( maybe verity => ( $settings->{minimum_verity} || undef ) ),
                                ( $settings->{case_sensitive} )
                                    ? ( synonym =>
                                        ( $settings->{skip_substring_search} )
                                            ? { -in   => \@terms }
                                            : { -glob => [ map { '*' . $_ . '*' } @terms ] }
                                    )
                                    : ( 'LOWER(synonym)' =>
                                        ( $settings->{skip_substring_search} )
                                            ? { '='   => [ map { \[ 'LOWER(?)', $_             ] } @terms ] }
                                            : { -glob => [ map { \[ 'LOWER(?)', '*' . $_ . '*' ] } @terms ] }
                                    )
                            },
                        )->run->column,
                    },
                ],
            },
        )->run->all({})->@*
    ) if ( $settings->{reverse_lookup} );

    return [
        map {
            $_->{types} = [];
            for my $type ( qw( ignored special ) ) {
                push( @{ $_->{types} }, $type ) if (
                    grep {
                        my $meaning = $_;
                        grep { $meaning->{type} eq $_ } $settings->{ $type . '_types' }->@*;
                    } $_->{meanings}->@*
                );
            }
            $_;
        }
        grep { $_->{meanings}->@* }
        map {
            delete $_->{word_id};
            delete $_->{redirect_id};

            $_->{meanings} = [
                grep { $_->{synonyms}->@* }
                map {
                    $_->{synonyms} = [
                        grep { $_->{verity} >= $settings->{minimum_verity} } $_->{synonyms}->@*
                    ];
                    $_;
                } from_json( $_->{meanings} )->@*
            ];
            $_;
        }
        @$matches
    ];
}

1;

=head1 NAME

QuizSage::Util::Material

=head1 SYNOPSIS

    use QuizSage::Util::Material qw( material_json text2words synonyms_of_term );

    my @words = text2words(
        q{Jesus asked, "What's (the meaning of) this: 'I and my Father are one.'"}
    )->@*;

    my %results = material_json( 'Acts 1-20 NIV', 'force' )->%*;

    my $thesaurus_matches = synonyms_of_term(
        'faith',
        {
            case_sensitive        => 0,
            skip_substring_search => 0,
            skip_term_splitting   => 0,
            minimum_verity        => 0,
            direct_lookup         => 1,
            reverse_lookup        => 1,
            ignored_types         => [ 'article', 'preposition' ],
            special_types         => ['pronoun'],
        },
    );

=head1 DESCRIPTION

This package provides exportable utility functions.

=head1 FUNCTIONS

=head2 material_json

This function accepts a material C<label> string and optional C<user> ID and
will build a JSON material data file using data from the material database.
A material label represents the reference range blocks, weights, and
translations for the expected output. For example:

    Romans 1-4; James (1) Romans 5-8 (1) ESV NASB* NASB1995 NIV

The function also accepts an optional C<force> boolean value to indicate if an
existing JSON file should be rebuilt. (Default is false.)

    my %results = material_json(
        label => 'Acts 1-20 NIV',
        force => 1,
    )->%*;

The function returns a hashref with C<label>, C<description>, C<json_file>,
and C<id> keys. The C<label> will be a canonical label, C<description> will be
the material description, and the C<json_file> is the file that was created or
recreated. The C<id> is the hash ID of the JSON file.

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

You can optionally pass in a true second value, which will cause the function
to skip lower-casing words.

=head2 synonyms_of_term

This method requires a term (which is a string of a partial word, single word,
or multiple space-separated words) and an optional settings hashref. It will
return thesaurus matches based on the input.

    my $thesaurus_matches = synonyms_of_term(
        'faith',
        {
            case_sensitive        => 0,
            skip_substring_search => 0,
            skip_term_splitting   => 0,
            minimum_verity        => 0,
            direct_lookup         => 1,
            reverse_lookup        => 1,
            ignored_types         => [ 'article', 'preposition' ],
            special_types         => ['pronoun'],
        },
    );
