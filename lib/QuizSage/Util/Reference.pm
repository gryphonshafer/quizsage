package QuizSage::Util::Reference;

use exact -conf, -fun;
use Digest;
use File::Path 'make_path';
use Mojo::File 'path';
use Mojo::JSON qw( to_json from_json );
use Omniframe::Class::Time;
use QuizSage::Model::Label;
use QuizSage::Util::Material 'text2words';

exact->exportable( qw( reference_data reference_html ) );

my $time = Omniframe::Class::Time->new;

fun reference_data (
    :$material_label    = undef,       # material label/description
    :$user_id           = undef,       # user ID from application database
    :$bible             = undef,       # acronym for memorized Bible
    :$cover             = 1,           # boolean; include cover page
    :$reference         = 1,           # boolean; include reference section
    :$reference_scope   = 'memorized', # enum: memorized, all
    :$whole             = 5,           # words for whole section
    :$chapter           = 3,           # words for chapter section
    :$phrases           = 4,           # words for phrases section
    :$concordance       = 0,           # boolean; include concordance
    :$concordance_scope = 'memorized', # enum: memorized, all
    :$mark_unique       = 0,           # boolean; mark unique words and 2-word phrases
    :$labels_to_markup  = '',          # labels to markup
    :$force             = 0,           # force data regeneration (and update JSON cache file)

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

    my $mlabel = QuizSage::Model::Label->new( maybe user_id => $user_id );
    my $parse  = $mlabel->parse( $material_label . ' ' . $bible );

    croak('Failed to parse material label/description')
        unless ( $parse and ref $parse eq 'HASH' and not exists $parse->{error} );

    my %bibles = map { $_ => 1 } map { @$_ } values $parse->{bibles}->%*;
    $bible     = ( delete $bibles{ $bible } ) ? $bible : undef;

    croak('Bible specified does not exist') unless $bible;

    my $description = $mlabel->descriptionate($parse);
    my $bibles      = [ $bible, sort keys %bibles ];
    my $id          = substr( Digest->new('SHA-256')->add(
        join( '|',
            $description,
            join( ',', @$bibles ),
            $cover,
            $reference,
            $reference_scope,
            $whole,
            $chapter,
            $phrases,
            $concordance,
            $concordance_scope,
            $mark_unique,
            $labels_to_markup,
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

    my $now       = time;
    my $json_path = path( join( '/',
        conf->get( qw{ config_app root_dir } ),
        conf->get( qw{ reference location json } ),
    ) );
    my $delete_if_before = $time->parse( conf->get( qw{ reference delete_if_before } ) )->{datetime}->epoch;
    $json_path->list->grep( sub ($file) {
        $file->stat->atime < $delete_if_before
    } )->each('remove');
    # remove any reference JSON files that haven't been accessed in the last N days
    my $atime_life = conf->get( qw{ reference atime_life } );
    $json_path->list->grep( sub ($file) {
        ( $now - $file->stat->atime ) / ( 60 * 60 * 24 ) > $atime_life
    } )->each('remove');

    my $json_file = $json_path->child( $id . '.json' );
    return from_json( $json_file->slurp('UTF-8') ) if ( -f $json_file and not $force );

    $labels_to_markup = ($labels_to_markup) ? [
        map {
            my $label = $mlabel->new->load({ name => $_ });
            +{
                name        => $_,
                description => $label->descriptionize,
                verses      => [
                    $mlabel->bible_ref->clear->simplify(0)->acronyms(1)->in(
                        $label->data->{label}
                    )->as_verses
                ],
            };
        }
        $mlabel->identify_aliases($labels_to_markup)->@*
    ] : [];

    my $labels_for_ref = sub ($ref_short) {
        return [
            map { chr( $_ + 96 ) }
            grep {
                grep { $ref_short eq $_ } $labels_to_markup->[ $_ - 1 ]{verses}->@*
            } 1 .. @$labels_to_markup
        ];
    };

    my $dq      = $mlabel->dq('material');
    my $content = [
        grep {
            my $verse = $_;
            @$bibles == grep { $verse->{bibles}{$_} } @$bibles
        }
        map {
            /^(?<book>.+)\s+(?<chapter>\d+):(?<verse>\d+)$/;
            my $ref_short = $mlabel->bible_ref->clear->simplify(0)->acronyms(1)->in($_)->refs;
            +{
                ref_long  => $_,
                ref_short => $ref_short,
                book      => $+{book},
                chapter   => $+{chapter},
                verse     => $+{verse},
                labels    => $labels_for_ref->($ref_short),
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

    my $uniques = {};
    if ($mark_unique) {
        for my $verse (@$content) {
            for my $bible ( keys $verse->{bibles}->%* ) {
                my %words = map { $_ => 1 } $verse->{bibles}{$bible}{words}->@*;
                my @words = keys %words;
                $uniques->{$bible}{ $words[$_] }++ for ( 0 .. @words - 1 );
            }
        }

        for my $bible ( keys %$uniques ) {
            $uniques->{$bible} = [
                grep { $uniques->{$bible}{$_} == 1 }
                keys %{ $uniques->{$bible} }
            ];
        }

        for my $verse (@$content) {
            for my $bible ( keys $verse->{bibles}->%* ) {
                $verse->{bibles}{$bible}{text} =~ s|\b($_)\b|\*$1/\*|gi for ( $uniques->{$bible}->@* );
                $verse->{bibles}{$bible}{text} =~ s|/\*|</span>|g;
                $verse->{bibles}{$bible}{text} =~ s|\*|<span class="word">|g;
            }
        }
    }

    my $data = {
        description => $description,
        cover       => $cover,
        bibles      => $bibles,
        id          => $id,
        labels      => $labels_to_markup,
        uniques     => $uniques,

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
        blocks => [ map {
            my $bible = $_;
            +{
                header => $bible,
                rows   => [ map { [
                    {
                        class  => 'ref',
                        text   => $bible . ' ' . $_->{ref_short},
                        labels => $_->{labels},
                    },
                    $_->{bibles}{$bible}{text},
                ] } $content->@* ],
            };
        } ( $reference_scope eq 'memorized' ) ? $bible : @$bibles ],
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
                                        class  => 'ref',
                                        text   => $this_bible . ' ' . $this_data->[0],
                                        labels => $this_data->[2],
                                    },
                                    $this_data->[1]{text},
                                )
                                : (
                                    join(
                                        ' ',
                                        grep { defined } @{ $this_data->[1]{words} }[ 0 .. $whole - 1 ]
                                    ),
                                    {
                                        class  => 'ref',
                                        text   => $this_bible . ' ' . $this_data->[0],
                                        labels => $this_data->[2],
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
                        $_->{labels},
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
                my $this_chapter = $verse->{book} . ' ' . $verse->{chapter};
                push( @chapters, $this_chapter ) unless ( $these_phrases->{$this_chapter} );
                for my $i ( 0 .. $verse->{bibles}{$this_bible}{words}->@* - $chapter + 1 ) {
                    my $j = $i + $chapter - 1;
                    last if ( $j >= $verse->{bibles}{$this_bible}{words}->@* );
                    push(
                        $these_phrases->{$this_chapter}{
                            join( ' ', @{ $verse->{bibles}{$this_bible}{words} }[ $i .. $j ] )
                        }->@*,
                        $verse->{ref_short},
                    );
                }
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
                                    class  => 'ref',
                                    text   => $this_bible . ' ' . $these_phrases->{$this_chapter}{$phrase}[0],
                                    labels => $labels_for_ref->(
                                        $these_phrases->{$this_chapter}{$phrase}[0]
                                    ),
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
                for my $i ( 0 .. $verse->{bibles}{$this_bible}{words}->@* - $phrases + 1 ) {
                    my $j = $i + $phrases - 1;
                    last if ( $j >= $verse->{bibles}{$this_bible}{words}->@* );
                    push(
                        $these_phrases->{
                            join( ' ', @{ $verse->{bibles}{$this_bible}{words} }[ $i .. $j ] )
                        }->@*,
                        $verse->{ref_short},
                    );
                }
            }

            +{
                header => $this_bible,
                rows   => [
                    map {
                        my $phrase = $_;
                        [
                            $phrase,
                            {
                                class  => 'ref',
                                text   => $this_bible . ' ' . $these_phrases->{$phrase}[0],
                                labels => $labels_for_ref->( $these_phrases->{$phrase}[0] ),
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
                                        labels    => $labels_for_ref->( $_->{ref_short} ),
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
        } ( $concordance_scope eq 'memorized' ) ? $bible : @$bibles ],
    } ) if $concordance;

    $data->{bible} = shift @{ $data->{bibles} };

    make_path( $json_file->dirname ) unless ( -d $json_file->dirname );
    $json_file->spew( to_json($data), 'UTF-8' );

    return $data;
}

sub reference_html ( $controller, $reference_data, $force = 0 ) {
    my $now       = time;
    my $html_path = path( join( '/',
        conf->get( qw{ config_app root_dir } ),
        conf->get( qw{ reference location html } ),
    ) );
    my $delete_if_before = $time->parse( conf->get( qw{ reference delete_if_before } ) )->{datetime}->epoch;
    $html_path->list->grep( sub ($file) {
        $file->stat->atime < $delete_if_before
    } )->each('remove');
    # remove any reference HTML files that haven't been accessed in the last N days
    my $atime_life = conf->get( qw{ reference atime_life } );
    $html_path->list->grep( sub ($file) {
        ( $now - $file->stat->atime ) / ( 60 * 60 * 24 ) > $atime_life
    } )->each('remove');

    my $html_file = $html_path->child( $reference_data->{id} . '.html' );

    my $html;
    unless ( -f $html_file and not $force ) {
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
        $html_file->spew( $html, 'UTF-8' );
    }
    else {
        $html = $html_file->slurp('UTF-8');
    }

    return $html;
}

1;

=head1 NAME

QuizSage::Util::Reference

=head1 SYNOPSIS

    use QuizSage::Util::Reference 'reference_data';

    my $reference_data = reference_data(
        label             => 'Luke ESV NIV', # material label/description
        user_id           => 42,             # user ID from application database
        bible             => 'NIV',          # acronym for memorized Bible
        cover             => 1,              # boolean; include cover page
        reference         => 1,              # boolean; include reference section
        reference_scope   => 'memorized',    # enum: memorized, all
        whole             => 5,              # words for whole section
        chapter           => 3,              # words for chapter section
        phrases           => 4,              # words for phrases section
        concordance       => 0,              # boolean; include concordance
        concordance_scope => 'memorized',    # enum: memorized, all
        mark_unique       => 0,              # boolean; mark unique words and 2-word phrases
        labels_to_markup  => undef,          # labels to markup
        force             => 0,              # force data regeneration
    );

=head1 DESCRIPTION

This package provides exportable reference material functions.

=head1 FUNCTION

=head2 reference_data

This function generates reference material.

    my $reference_data = reference_data(
        label             => 'Luke ESV NIV', # material label/description
        user_id           => 42,             # user ID from application database
        bible             => 'NIV',          # acronym for memorized Bible
        cover             => 1,              # boolean; include cover page
        reference         => 1,              # boolean; include reference section
        reference_scope   => 'memorized',    # enum: memorized, all
        whole             => 5,              # words for whole section
        chapter           => 3,              # words for chapter section
        phrases           => 4,              # words for phrases section
        concordance       => 0,              # boolean; include concordance
        concordance_scope => 'memorized',    # enum: memorized, all
        mark_unique       => 0,              # boolean; mark unique words and 2-word phrases
        labels_to_markup  => undef,          # labels to markup
        force             => 0,              # force data regeneration
    );

=head2 reference_html

This function requires an application controller instance and the output from
C<reference_data>. It will render and return HTML.
