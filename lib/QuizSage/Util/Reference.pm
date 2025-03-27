package QuizSage::Util::Reference;

use exact -conf, -fun;
use Digest;
use File::Path 'make_path';
use Mojo::File 'path';
use Mojo::JSON qw( encode_json decode_json );
use QuizSage::Model::Label;
use QuizSage::Util::Material 'text2words';

exact->exportable( qw( reference_data reference_html ) );

fun reference_data (
    :$material_label = undef, # material label/description
    :$user_id        = undef, # user ID from application database
    :$bible          = undef, # acronym for memorized Bible
    :$cover          = 1,     # boolean; include cover page
    :$reference      = 1,     # boolean; include reference section
    :$whole          = 5,     # words for whole section
    :$chapter        = 3,     # words for chapter section
    :$phrases        = 4,     # words for phrases section
    :$concordance    = 0,     # boolean; include concordance
    :$force          = 0,     # force data regeneration (and update JSON cache file)

    :$page_width               = 8.5,
    :$page_height              = 11,
    :$page_right_margin_left   = 1,
    :$page_right_margin_right  = 0.5,
    :$page_right_margin_top    = 0.5,
    :$page_right_margin_bottom = 0.5,
    :$page_left_margin_left    = 0.5,
    :$page_left_margin_right   = 1,
    :$page_left_margin_top     = 0.5,
    :$page_left_margin_bottom  = 0.5,
) {
    croak('Not all required parameters provided') unless (
        $material_label and $bible and ( $reference or $whole or $chapter or $phrases or $concordance )
    );

    $bible = uc $bible;

    my $mlabel  = QuizSage::Model::Label->new( maybe user_id => $user_id );
    my $parse  = $mlabel->parse( $material_label . ' ' . $bible );
    my %bibles = map { $_ => 1 } map { @$_ } values $parse->{bibles}->%*;
    $bible     = ( delete $bibles{ $bible } ) ? $bible : undef;

    croak('Bible specified does not exist') unless $bible;

    my $description = $mlabel->descriptionize( join( '; ', map { $_->{range}->@* } $parse->{ranges}->@* ) );
    my $bibles      = [ $bible, sort keys %bibles ];
    my $id          = substr( Digest->new('SHA-256')->add(
        join( '|',
            $description,
            join( ',', @$bibles ),
            $cover,
            $reference,
            $whole,
            $chapter,
            $phrases,
            $concordance,
            $page_width,
            $page_height,
            $page_right_margin_left,
            $page_right_margin_right,
            $page_right_margin_top,
            $page_right_margin_bottom,
            $page_left_margin_left,
            $page_left_margin_right,
            $page_left_margin_top,
            $page_left_margin_bottom,
        )
    )->hexdigest, 0, 16 );

    my $now = time;
    if ( $now < $time->parse( conf->get( qw{ reference delete_if_before } ) )->{datetime}->epoch ) {
        $json_path->list->each('remove');
    }
    else {
        # remove any reference JSON files that haven't been accessed in the last N days
        my $atime_life = conf->get( qw{ reference atime_life } );
        my $json_path  = path( join( '/',
            conf->get( qw{ config_app root_dir } ),
            conf->get( qw{ reference location json } ),
        ) );
        $json_path->list->grep( sub ($file) {
            ( $now - $file->stat->atime ) / ( 60 * 60 * 24 ) > $atime_life
        } )->each('remove');
    }

    my $json_file = $json_path->child( $id . '.json' );
    return decode_json( $json_file->slurp ) if ( -f $json_file and not $force );

    my $dq      = $mlabel->dq('material');
    my $content = [
        grep {
            my $verse = $_;
            @$bibles == grep { $verse->{bibles}{$_} } @$bibles
        }
        map {
            /^(?<book>.+)\s+(?<chapter>\d+):(?<verse>\d+)$/;
            +{
                ref_long  => $_,
                ref_short => $mlabel->bible_ref->clear->simplify(0)->acronyms(1)->in($_)->refs,
                book      => $+{book},
                chapter   => $+{chapter},
                verse     => $+{verse},
                bibles    => {
                    map {
                        $_->{words}  = text2words $_->{text};
                        $_->{string} = join( ' ', $_->{words}->@* );

                        delete $_->{bible} => $_;
                    }
                    $dq->get(
                        [
                            [ [ 'verse' => 'v' ] ],
                            [ { 'bible' => 't' }, 'bible_id' ],
                            [ { 'book'  => 'b' }, 'book_id'  ],
                        ],
                        [ [ 't.acronym', 'bible' ], 'v.text' ],
                        {
                            't.acronym' => $bibles,
                            'b.name'    => $+{book},
                            'v.chapter' => $+{chapter},
                            'v.verse'   => $+{verse},
                        },
                    )->run->all({})->@*
                },
            };
        } $mlabel->bible_ref->clear->simplify(0)->acronyms(0)->in($description)->as_verses->@*
    ];

    my $data = {
        description => $description,
        cover       => $cover,
        bibles      => $bibles,
        id          => $id,

        page_width               => $page_width,
        page_height              => $page_height,
        page_right_margin_left   => $page_right_margin_left,
        page_right_margin_right  => $page_right_margin_right,
        page_right_margin_top    => $page_right_margin_top,
        page_right_margin_bottom => $page_right_margin_bottom,
        page_left_margin_left    => $page_left_margin_left,
        page_left_margin_right   => $page_left_margin_right,
        page_left_margin_top     => $page_left_margin_top,
        page_left_margin_bottom  => $page_left_margin_bottom,
    };

    push( $data->{sections}->@*, {
        header => 'Reference Material',
        blocks => [ {
            header => $bible,
            rows   => [ map { [
                {
                    class => 'ref',
                    text  => $bible . ' ' . $_->{ref_short},
                },
                $_->{bibles}{$bible}{text},
            ] } $content->@* ],
        } ],
    } ) if $reference;

    push( $data->{sections}->@*, {
        header => ( ( $whole > 1 )
            ? 'Alphabetical Material from First ' . $whole . ' Words'
            : 'Alphabetical Material from First Word'
        ),
        blocks => [ map {
            my $this_bible = $_;
            +{
                header => $this_bible,
                rows   => [
                    map {
                        my $this_data = $_;
                        [
                            ( $this_bible eq $bible )
                                ? (
                                    {
                                        class => 'ref',
                                        text  => $this_bible . ' ' . $this_data->[0],
                                    },
                                    $this_data->[1]{text},
                                )
                                : (
                                    join(
                                        ' ',
                                        grep { defined } @{ $this_data->[1]{words} }[ 0 .. $whole - 1 ]
                                    ),
                                    {
                                        class => 'ref',
                                        text  => $this_bible . ' ' . $this_data->[0],
                                    },
                                    (
                                        grep { $_->{ref_short} eq $this_data->[0] } $content->@*
                                    )[0]{bibles}{$bible}{text},
                                ),
                        ],
                    }
                    sort { ( $a->[1]{string} || '' ) cmp ( $b->[1]{string} || '' ) }
                    map { [
                        $_->{ref_short},
                        $_->{bibles}{$this_bible},
                    ] } $content->@*,
                ],
            };
        } @$bibles ],
    } ) if $whole;

    push( $data->{sections}->@*, {
        header => ( ( $chapter > 1 )
            ? $chapter . '-Word Unique Phrases by Chapter'
            : 'Unique Words by Chapter'
        ),
        blocks => [ map {
            my $this_bible = $_;
            my $these_phrases;
            my @chapters;

            for my $verse ( $content->@* ) {
                my @phrases      = $verse->{bibles}{$this_bible}{words}->@*;
                my $this_chapter = $verse->{book} . ' ' . $verse->{chapter};

                push( @chapters, $this_chapter ) unless ( $these_phrases->{$this_chapter} );
                push(
                    $these_phrases->{$this_chapter}->{ join( ' ', splice( @phrases, 0, $chapter ) ) }->@*,
                    $verse->{ref_short},
                ) while ( @phrases >= $chapter );
            }

            map {
                my $this_chapter = $_;
                +{
                    header => $this_bible . ' ' . $this_chapter,
                    rows   => [
                        map {
                            my $phrase = $_;
                            [
                                $phrase,
                                {
                                    class => 'ref',
                                    text  => $this_bible . ' ' . $these_phrases->{$this_chapter}{$phrase}[0],
                                },
                                (
                                    grep {
                                        $_->{ref_short} eq $these_phrases->{$this_chapter}{$phrase}[0]
                                    } $content->@*
                                )[0]{bibles}{$bible}{text},
                            ];
                        } sort
                            grep { $these_phrases->{$this_chapter}{$_}->@* == 1 }
                            keys %{ $these_phrases->{$this_chapter} },
                    ],
                }
            }
            grep { $these_phrases->{$_} }
            @chapters;
        } @$bibles ],
    } ) if $chapter;

    push( $data->{sections}->@*, {
        header => ( ( $phrases > 1 )
            ? 'Global ' . $phrases . '-Word Unique Phrases'
            : 'Global Unique Words'
        ),
        blocks => [ map {
            my $this_bible = $_;
            my $these_phrases;

            for my $verse ( $content->@* ) {
                my @phrases = $verse->{bibles}{$this_bible}{words}->@*;
                push(
                    $these_phrases->{ join( ' ', splice( @phrases, 0, $phrases ) ) }->@*,
                    $verse->{ref_short},
                ) while ( @phrases >= $phrases );
            }

            +{
                header => $this_bible,
                rows   => [
                    map {
                        my $phrase = $_;
                        [
                            $phrase,
                            {
                                class => 'ref',
                                text  => $this_bible . ' ' . $these_phrases->{$phrase}[0],
                            },
                            (
                                grep { $_->{ref_short} eq $these_phrases->{$phrase}[0] } $content->@*
                            )[0]{bibles}{$bible}{text},
                        ];
                    } sort grep { $these_phrases->{$_}->@* == 1 } keys %$these_phrases,
                ],
            };
        } @$bibles ],
    } ) if $phrases;

    push( $data->{sections}->@*, {
        header => 'Concordance',
        blocks => [ map {
            my $this_bible = $_;
            my $these_words;

            for my $verse ( $content->@* ) {
                push( $these_words->{$_}->@*, $verse->{ref_short} )
                    for ( $verse->{bibles}{$this_bible}{words}->@* );
            }

            +{
                header => $this_bible,
                rows   => [
                    map {
                        +{
                            word   => $_,
                            verses => [ map {
                                my $ref_short = $_;
                                map {
                                    +{
                                        ref_short => $_->{ref_short},
                                        text      => $_->{bibles}{$bible}{text},
                                    };
                                }
                                grep {
                                    $_->{ref_short} eq $ref_short
                                } $content->@*;
                            } $these_words->{$_}->@* ],
                        }
                    } sort keys %$these_words
                ],
            };
        } @$bibles ],
    } ) if $concordance;

    $data->{bible} = shift @{ $data->{bibles} };

    make_path( $json_file->dirname ) unless ( -d $json_file->dirname );
    $json_file->spew( encode_json($data) );

    return $data;
}

sub reference_html ( $controller, $reference_data ) {
    my $now       = time;
    my $html_path = path( join( '/',
        conf->get( qw{ config_app root_dir } ),
        conf->get( qw{ reference location html } ),
    ) );
    if ( $now < $time->parse( conf->get( qw{ reference delete_if_before } ) )->{datetime}->epoch ) {
        $html_path->list->each('remove');
    }
    else {
        # remove any reference HTML files that haven't been accessed in the last N days
        my $atime_life = conf->get( qw{ reference atime_life } );
        $html_path->list->grep( sub ($file) {
            ( $now - $file->stat->atime ) / ( 60 * 60 * 24 ) > $atime_life
        } )->each('remove');
    }

    my $html_file = $html_path->child( $reference_data->{id} . '.html' );

    my $html;
    unless ( -f $html_file ) {
        $html = $controller->app->tt_html(
            'reference/generator.html.tt',
            {
                page => {
                    no_defaults => 1,
                    lang        => 'en',
                    charset     => 'utf-8',
                    viewport    => 1,
                },
                $reference_data->%*,
            },
        );

        make_path( $html_file->dirname ) unless ( -d $html_file->dirname );
        $html_file->spew($html);
    }
    else {
        $html = $html_file->slurp;
    }

    return $html;
}

1;

=head1 NAME

QuizSage::Util::Reference

=head1 SYNOPSIS

    use QuizSage::Util::Reference 'reference_data';

    my $reference_data = reference_data(
        label        => 'Luke ESV NIV', # material label/description
        user_id      => 42,             # user ID from application database
        bible        => 'NIV',          # acronym for memorized Bible
        cover        => 1,              # boolean; include cover page
        reference    => 1,              # boolean; include reference section
        whole        => 5,              # words for whole section
        chapter      => 3,              # words for chapter section
        phrases      => 4,              # words for phrases section
        concordance  => 0,              # boolean; include concordance
        force        => 0,              # force data regeneration
    );

=head1 DESCRIPTION

This package provides exportable reference material functions.

=head1 FUNCTION

=head2 reference_data

This function generates reference material.

    my $reference_data = reference_data(
        label        => 'Luke ESV NIV', # material label/description
        user_id      => 42,             # user ID from application database
        bible        => 'NIV',          # acronym for memorized Bible
        cover        => 1,              # boolean; include cover page
        reference    => 1,              # boolean; include reference section
        whole        => 5,              # words for whole section
        chapter      => 3,              # words for chapter section
        phrases      => 4,              # words for phrases section
        concordance  => 0,              # boolean; include concordance
        force        => 0,              # force data regeneration
    );

=head2 reference_html

This function requires an application controller instance and the output from
C<reference_data>. It will render and return HTML.
