#!/usr/bin/env perl
use exact;
use DDP;
use Parse::RecDescent;

my $grammar = q{
    label: distributive | part(s)

    distributive: part(s) '/' part(s)
        { [ +{ type => $item[0], prefix => $item[1], suffix => $item[3] } ] }

    part: weighted_set | block | filter | intersection | addition | text
        { $item[1] }

    weighted_set: weighted_parts '(' weight ')'
        { +{ type => $item[0], parts => $item[1], weight => $item[3] } }

    weighted_parts: ( block | filter | intersection | addition | text )(s)

    weight: contains_a_number

    block: '[' label ']'
        { +{ type => $item[0], parts => $item[2] } }

    filter: '|' anything_left_over
        { +{ type => 'filter', value => $item[2] } }

    intersection: '~' anything_left_over
        { +{ type => 'intersection', value => $item[2] } }

    addition: '+' number maybe_verse_abbrv
        { +{ type => 'addition', value => $item[2] } }

    text: anything_left_over
        { +{ type => 'text', value => $item[1] } }

    contains_a_number : /(?=.*\d)[^)]*/
    anything_left_over: /[^\/\[\]|~\(\)\+]+/
    number            : /\d+/
    maybe_verse_abbrv : /(?:v[ers]+)?/i
    start             : label /\Z/
        { +{ type => 'label', parts => $item[1] } }
};

my @inputs = (
    'Romans 1-3; James 1:2-2:12',
    'Romans 1-3 (40%) James 1:2-2:12 (60%)',
    'Romans 1-3; James 1:2-2:12 | Romans 2-6',
    'Romans 1-3 (40%) James 1:2-2:12 (60%) ~ Romans 2-6',
    'Romans 1-5 ~ Romans 4-7 (1)',
    'Romans 1-3 ~ Romans 2-6 (40%) James 1:2-2:12 +1 verse (60%)',
    '[ Romans 1-5 (30%) Romans 6-10 (70%) ] +1 Verse',
    'Romans 1-5 [ Romans 6-10 | Romans 18 ] ~ Romans 4-7',
    'Romans 1-5 (3) [ [ Romans 6-10 ] | Romans 18 ] (1) ~ Romans 4-7',
    'Romans 1 (1) / Club 100 (1)',
    'Romans 1-5 (1) Romans 6-10 (2) Romans 11-13 (3) / Club 100 (1) Club 300 (2) All (3)',
    'Romans 1-5 (1) Romans 6-10 (2) [ Romans 11-13 (3) / Club 100 (1) Club 300 (2) All (3) ]',
    '[ Romans 1 (1) / Club 100 (1) ] / Club 300 (2)',
);

my $nodes;
$nodes = sub ($node) {
    if ( ref $node eq 'ARRAY' ) {
        $nodes->($_) for (@$node);
    }
    elsif ( ref $node eq 'HASH' ) {
        if ( $node->{type} eq 'weighted_set' ) {
            $node->{weight} =~ s/\D+//g;
            $node->{weight} = 0 + $node->{weight};
        }
        if (
            $node->{type} eq 'text' or
            $node->{type} eq 'filter' or
            $node->{type} eq 'intersection'
        ) {
            $node->{value} =~ s/\s+/ /g;
            $node->{value} =~ s/(?:^\s+|\s+$)//g;
        }
        else {
            $nodes->( $node->{$_} ) for ( keys %$node );
        }
    }
};

for my $input (@inputs) {
    say "> $input";
    my $result = Parse::RecDescent->new($grammar)->start($input);
    $nodes->($result);
    p $result;
}
