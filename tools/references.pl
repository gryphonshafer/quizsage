#!/usr/bin/env perl
use exact -cli, -conf;
use Mojo::JSON 'decode_json';
use Omniframe;
use QuizSage::Model::Label;
use QuizSage::Model::User;
use QuizSage::Util::Material 'text2words';
use Template;

my $opt = options( qw{
    label|l=s
    email|e=s
    bible|b=s
    reference|r
    whole|w=i
    chapter|c=i
    phrases|p=i
    all|a
} );

if ( $opt->{all} ) {
    $opt->{reference} = 1;
    $opt->{whole}   //= 5;
    $opt->{chapter} //= 3;
    $opt->{phrases} //= 4;
}

pod2usage('Not all required parameters provided') unless (
    $opt->{label} and $opt->{bible} and
    ( $opt->{reference} or $opt->{whole} or $opt->{chapter} or $opt->{phrases} )
);

$opt->{bible} = uc $opt->{bible};

my $user_id;
if ( $opt->{email} ) {
    try {
        $user_id = QuizSage::Model::User->new->load({ email => $opt->{email} })->id;
    }
    catch ($e) {
        die Omniframe->with_roles('Omniframe::Role::Output')->new->deat($e) . "\n";
    }
}

my $label  = QuizSage::Model::Label->new( maybe user_id => $user_id );
my $parse  = $label->parse( $opt->{label} . ' ' . $opt->{bible} );
my %bibles = map { $_ => 1 } map { @$_ } values $parse->{bibles}->%*;
my $bible  = ( delete $bibles{ $opt->{bible} } ) ? $opt->{bible} : undef;

pod2usage('Bible specified does not exist') unless $bible;

my $description = $label->descriptionize( join( '; ', map { $_->{range}->@* } $parse->{ranges}->@* ) );
my $bibles      = [ $bible, sort keys %bibles ];
my $dq          = $label->dq('material');
my $content     = [
    map {
        /^(?<book>.+)\s+(?<chapter>\d+):(?<verse>\d+)$/;
        +{
            ref_long  => $_,
            ref_short => $label->bible_ref->clear->simplify(0)->acronyms(1)->in($_)->refs,
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
    } $label->bible_ref->clear->simplify(0)->acronyms(0)->in($description)->as_verses->@*
];

my $data = {
    description => $description,
    bibles      => $bibles,
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
} ) if ( $opt->{reference} );

push( $data->{sections}->@*, {
    header => 'Alphabetical Material from First ' . $opt->{whole} . ' Words',
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
                                join( ' ', @{ $this_data->[1]{words} }[ 0 .. $opt->{whole} - 1 ] ),
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
                sort { $a->[1]{string} cmp $b->[1]{string} }
                map { [
                    $_->{ref_short},
                    $_->{bibles}{$this_bible},
                ] } $content->@*,
            ],
        };
    } @$bibles ],
} ) if ( $opt->{whole} );

push( $data->{sections}->@*, {
    header => $opt->{chapter} . '-Word Key Phrases by Chapter',
    blocks => [ map {
        my $this_bible = $_;
        my $phrases;
        my @chapters;

        for my $verse ( $content->@* ) {
            my @phrases = $verse->{bibles}{$this_bible}{words}->@*;
            my $chapter = $verse->{book} . ' ' . $verse->{chapter};

            push( @chapters, $chapter ) unless ( $phrases->{$chapter} );
            push(
                $phrases->{$chapter}->{ join( ' ', splice( @phrases, 0, $opt->{chapter} ) ) }->@*,
                $verse->{ref_short},
            ) while ( @phrases >= $opt->{chapter} );
        }

        map {
            my $chapter = $_;
            +{
                header => $this_bible . ' ' . $chapter,
                rows   => [
                    map {
                        my $phrase = $_;
                        [
                            $phrase,
                            {
                                class => 'ref',
                                text  => $this_bible . ' ' . $phrases->{$chapter}{$phrase}[0],
                            },
                            (
                                grep { $_->{ref_short} eq $phrases->{$chapter}{$phrase}[0] } $content->@*
                            )[0]{bibles}{$bible}{text},
                        ];
                    } sort grep { $phrases->{$chapter}{$_}->@* == 1 } keys %{ $phrases->{$chapter} },
                ],
            }
        }
        grep { $phrases->{$_} }
        @chapters;
    } @$bibles ],
} ) if ( $opt->{chapter} );

push( $data->{sections}->@*, {
    header => 'Global ' . $opt->{phrases} . '-Word Key Phrases',
    blocks => [ map {
        my $this_bible = $_;
        my $phrases;

        for my $verse ( $content->@* ) {
            my @phrases = $verse->{bibles}{$this_bible}{words}->@*;
            push(
                $phrases->{ join( ' ', splice( @phrases, 0, $opt->{phrases} ) ) }->@*,
                $verse->{ref_short},
            ) while ( @phrases >= $opt->{phrases} );
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
                            text  => $this_bible . ' ' . $phrases->{$phrase}[0],
                        },
                        (
                            grep { $_->{ref_short} eq $phrases->{$phrase}[0] } $content->@*
                        )[0]{bibles}{$bible}{text},
                    ];
                } sort grep { $phrases->{$_}->@* == 1 } keys %$phrases,
            ],
        };
    } @$bibles ],
} ) if ( $opt->{phrases} );

my $tt = Template->new;
$tt->process( \*DATA, $data ) or die $tt->error . "\n";

=head1 NAME

references.pl - Build a "references" HTML document

=head1 SYNOPSIS

    references.pl OPTIONS
        -l, --label     MATERIAL_LABEL  # required
        -e, --email     USER_EMAIL
        -b, --bible     BIBLE_ACRONYM   # required
        -r, --reference
        -w, --whole     WORD_COUNT
        -c, --chapter   KEY_WORD_COUNT
        -p, --phrases   KEY_WORD_COUNT
        -a, --all
        -h, --help
        -m, --man

=head1 DESCRIPTION

This program will build a "references" HTML document based on a material label
and optionally a user (identitied by email). The generated HTML should be
suitable for printing.

=head2 -l, --label

A material label.

=head2 -e, --email

An email address that's used to identify a user. This is only useful in the case
where the material label includes an alias that's private to a user.

=head2 -b, --bible

A Bible acronym to indicate the quizzer-memorized translation.

=head2 -r, --reference

Include a "reference" section in the output, which is the content of the
material per Bible in Biblical order.

=head2 -w, --whole

Include a "whole" section in the output, which is the content of the
material per Bible in alphabetical-by-verse-text order. The word count is the
length of the introductory phrase printed from each translation.

=head2 -c, --chapter

Include a "chapter" section in the output, which is the content of the
material per Bible per chapter per multi-word key phrase. The key word count is
the length of the multi-word key phrase.

=head2 -p, --phrases

Include a "phrases" section in the output, which is the content of the
material per Bible per multi-word key phrase. The key word count is the length
of the multi-word key phrase.

=head2 -a, --all

This flag is the equivalent of setting C<reference>, C<whole>, C<chapter>, and
C<phrases>.

=cut

__DATA__
<!DOCTYPE html>
<html lang="en-US">
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">

        <style>
            body {
                font-family     : sans-serif;
                font-size       : 13px;
                background-color: white;
                color           : black;
            }
            h1 {
                font-size : 24px;
                display   : block;
                width     : fit-content;
                margin    : 0 auto;
                text-align: center;
            }
            h1 span.bibles {
                display   : block;
                font-size : 20px;
            }
            h1 ul.sections {
                display   : block;
                font-size : 16px;
                width     : fit-content;
                margin    : 1em auto 0 auto;
                text-align: left;
            }
            h2 {
                font-size  : 20px;
                padding-top: 1rem;
                margin     : 0 0 -1em 0;
            }
            h3 {
                font-size : 18px;
                text-align: right;
            }
            table {
                border-collapse: collapse;
            }
            td {
                font-family   : serif;
                vertical-align: top;
                font-size     : 16px;
                line-height   : 16px;
                border-top    : 1px solid #f0f0f0;
                border-bottom : 1px solid #f0f0f0;
                text-indent   : -1em;
                padding-left  : 1em;
                padding-bottom: 2px;
            }
            td.ref {
                font-family: sans-serif;
                width      : 6rem;
                font-size  : 13px;
                line-height: 19px;
            }
            @media print {
                h1 {
                    padding-top: calc(30vh);
                    font-size  : 36px;
                }
                h1 span.bibles {
                    font-size : 30px;
                    margin-top: 2em;
                }
                h1 ul.sections {
                    margin-top: 4em;
                }
                h2 {
                    page-break-before: always;
                }
            }
        </style>

        [%
            bible = bibles.shift;
            title = description _ ' ' _ bible _ ' ' _ ' with ' _ bibles.join(', ');
        %]
        <title>[% title %]</title>
    </head>
    <body>
        <h1>
            <span class="description">[% description %]</span>
            <span class="bibles">[% bible %] with [% bibles.join(', ') %]</span>
            <ul class="sections">
                [% FOR section IN sections %]
                    <li>[% section.header %]</li>
                [% END %]
            </ul>
        </h1>
        [% FOR section IN sections %]
            <h2>[% section.header %]</h2>
            [% FOR block IN section.blocks %]
                <h3>[% block.header %]</h3>
                <table>
                    [% FOR row IN block.rows %]
                        <tr>
                            [% FOR cell IN row %]

                                [% IF cell.text %]
                                    <td class="[% cell.class %]">[% cell.text %]</td>
                                [% ELSE %]
                                    <td>[% cell %]</td>
                                [% END %]

                            [% END %]
                        </tr>
                    [% END %]
                </table>
            [% END %]
        [% END %]
    </body>
</html>
