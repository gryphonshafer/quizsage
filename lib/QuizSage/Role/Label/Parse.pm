package QuizSage::Role::Label::Parse;

use exact -role;
use Math::Prime::Util 'divisors';
use Omniframe::Util::Data 'node_descend';
use Parse::RecDescent;

with 'QuizSage::Role::Label::Bible';

my $label_prd_obj = Parse::RecDescent->new( q{
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
        { +{ type => 'addition', amount => $item[2] } }

    text: anything_left_over
        { +{ type => 'text', value => $item[1] } }

    contains_a_number : /(?=.*\d)[^)]*/
    anything_left_over: /[^\/\[\]|~\(\)\+]+/
    number            : /\d+/
    maybe_verse_abbrv : /(?:v[ers]+)?/i
    start             : label /\Z/
        { +{ type => 'label', parts => $item[1] } }
} );

sub parse (
    $self,
    $input   = undef,
    $user_id = undef,
    $aliases = undef,
) {
    $input   //= $self->data->{label} if ( $self->can('data') );
    $user_id //= $self->user_id       if ( $self->can('user_id') );

    return {} unless ( defined $input );

    # get aliases to use for this parsing
    $aliases //=
        ( $self->user_aliases and $user_id and $self->user_id and $user_id == $self->user_id )
            ? $self->user_aliases :
        ( not $self->user_aliases and $user_id and $self->user_id and $user_id == $self->user_id )
            ? $self->user_aliases( $self->aliases($user_id) )->user_aliases :
            $self->aliases($user_id);

    # tokenize any aliases
    my $tokenized_aliases = [];
    for my $alias (@$aliases) {
        ( my $regex_core = quotemeta( $alias->{name} ) ) =~ s/\s+/s+/g;
        my $chr = chr( 57344 + @$tokenized_aliases );
        push( @$tokenized_aliases, $alias ) if ( $input =~ s/(?<=^|\b|\W)$regex_core(?=$|\b|\W)/ $chr /gi );
    }

    # store off any bibles
    my $bibles;
    if ( ref $self->bible_acronyms eq 'ARRAY' and $self->bible_acronyms->@* ) {
        my $bible_re = '\b(?<bible>(?:' . join( '|', $self->bible_acronyms->@* ) . ')(?:(?:\s*\*+)|\b))';
        while ( $input =~ s/$bible_re//i ) {
            my $bible = uc $+{bible};
            $bibles->{ ( $bible =~ s/\s*\*+// ) ? 'auxiliary' : 'primary' }{$bible} = 1;
        }
    }
    if ($bibles) {
        $bibles->{primary}   = [ sort keys $bibles->{primary}->%*   ] if ( $bibles->{primary}   );
        $bibles->{auxiliary} = [ sort keys $bibles->{auxiliary}->%* ] if ( $bibles->{auxiliary} );
    }

    # parse input into a data structure
    my $data = $label_prd_obj->start($input);

    return ($data)
        ? {
            parts => $self->_parse_parts_simplify(
                $self->_parse_parts_cleanup(
                    $data->{parts},
                    $aliases,
                    $tokenized_aliases,
                ),
                $aliases,
            ),
            maybe bibles => $bibles,
        }
        : { error => 'Failed to parse input string' };
}

sub _sort_aliases_for_display ($aliases) {
    return [
        map { $_->[1] }
        sort {
            $a->[0] cmp $b->[0] or
            $a->[1]{name} cmp $b->[1]{name}
        }
        map {
            ( my $sort = $_->{name} ) =~ s/[^\w\s]+//g;
            [ $sort, $_ ];
        }
        @$aliases
    ];
}

sub _parse_parts_cleanup ( $self, $parts, $aliases, $tokenized_aliases ) {
    try {
        node_descend(
            $parts,
            [ 'post', 'array', sub ($node) {
                # set weights via lowest common denominator (from largest common factor)
                if ( my @weighted_sets = grep { $_->{type} and $_->{type} eq 'weighted_set' } @$node ) {
                    $_->{weight} =~ s/\D+//g for (@weighted_sets);
                    my %factors;
                    $factors{$_}++ for ( map { divisors( $_->{weight} ) } @weighted_sets );
                    my ($largest_common_factor) =
                        sort { $b <=> $a }
                        grep { $factors{$_} == @weighted_sets }
                        keys %factors;
                    $_->{weight} /= $largest_common_factor for (@weighted_sets);

                    # find any text or block nodes after weighted blocks and move into a weighted block of 1
                    for ( 0 .. $#{$node} ) {
                        my $this = $node->[$_];
                        next unless (
                            $this->{type} and
                            ( $this->{type} eq 'text' or $this->{type} eq 'block' )
                        );

                        splice( @$node, $_, $#{$node}, {
                            type   => 'weighted_set',
                            weight => 1,
                            parts  => [ @$node[ $_ .. $#{$node} ] ],
                        } );
                        last;
                    }

                    # remove weight if there's only 1 weighted set of anything that can be weighted in node
                    my @weighted_set_indexes =
                        grep { $node->[$_]{type} eq 'weighted_set' }
                        0 .. $#{$node};
                    splice(
                        @$node,
                        $weighted_set_indexes[0],
                        1,
                        $node->[ $weighted_set_indexes[0] ]{parts}->@*,
                    ) if ( @weighted_set_indexes == 1 );
                }
            } ],
            [ 'wrap', 'hash', sub ( $node, $callback ) {
                if (
                    $node->{type} and (
                        $node->{type} eq 'text' or
                        $node->{type} eq 'filter' or
                        $node->{type} eq 'intersection'
                    )
                ) {
                    die 'Failed to parse ' . $node->{type} . ' node' unless ( defined $node->{value} );

                    # detokenize any aliases
                    while ( $node->{value} =~ s/([\x{E000}-\x{F8FF}])// ) {
                        if ( my $alias = $tokenized_aliases->[ ord($1) - 57344 ] ) {
                            {
                                use warnings FATAL => 'recursion';
                                $alias->{parts} //= $self->parse(
                                    $alias->{label},
                                    undef,
                                    $aliases,
                                )->{parts};
                            }
                            push( $node->{aliases}->@*, {
                                map { $_ => $alias->{$_} } qw( name label parts )
                            } );
                        }
                    }

                    # sort any aliases by name
                    $node->{aliases} = _sort_aliases_for_display( $node->{aliases} ) if ( $node->{aliases} );

                    $node->{special} = 'All' if ( $node->{value} =~ s/\b(?:
                        All|
                        Full|
                        Full\s+Material|
                        Everything|
                        Each|
                        Every
                    )\b//ix );

                    # canonicalize refs
                    my $refs = $self->canonicalize_refs( delete $node->{value} );
                    $node->{refs} = $refs if ($refs);

                    die 'Failed to parse ' . $node->{type} . ' node'
                        unless ( $node->{refs} or $node->{aliases} or $node->{special} );
                }
                else {
                    $callback->();
                }
            } ],
        );
    }
    catch ($e) {
        return {
            error => (
                ( index( $e, 'Deep recursion ' ) == 0 )
                    ? 'Aliases reference each other to cause deep recursion'
                    : deat $e,
            ),
        };
    }

    return $parts;
}

sub _parse_parts_simplify ( $self, $parts, $aliases ) {
    return node_descend(
        $parts,
        [ 'post', 'array', sub ($node) {
            # block that doesn't need to be a block de-blocked
            splice( @$node, $_, 1, $node->[$_]{parts}->@* ) for (
                grep {
                    $node->[$_]{type} and $node->[$_]{type} eq 'block' and
                    not grep {
                        $_->{type} and (
                            $_->{type} eq 'filter' or
                            $_->{type} eq 'intersection' or
                            $_->{type} eq 'addition' or
                            $_->{type} eq 'distributive' or
                            $_->{type} eq 'weighted_set'
                        )
                    } $node->[$_]{parts}->@*
                }
                0 .. $#{$node}
            );

            # multiple intersections/filters in single scope merged
            my $certain_nodes = {
                map {
                    my $type = $_;
                    $type => [ grep { $_->{type} and $_->{type} eq $type } @$node ];
                }
                qw( text intersection filter )
            };
            if (
                $certain_nodes->{text}->@* > 1 or
                $certain_nodes->{intersection}->@* > 1 or
                $certain_nodes->{filter}->@* > 1
            ) {
                my @leftovers =
                    grep {
                        $_->{type} and
                        $_->{type} ne 'text' and
                        $_->{type} ne 'intersection' and
                        $_->{type} ne 'filter'
                    } @$node;

                @$node = ();

                my $type_simplify = sub ($type) {
                    my $refs = $self->canonicalize_refs(
                        map { $_->{refs} } grep { $_->{refs} } $certain_nodes->{$type}->@*
                    );

                    my $aliases = _sort_aliases_for_display( [
                        map { $_->{aliases}->@* } grep { $_->{aliases} } $certain_nodes->{$type}->@*
                    ] );

                    push( @$node, {
                        type          => $type,
                        maybe refs    => ( $refs // undef ),
                        maybe aliases => ( (@$aliases) ? $aliases : undef ),
                    } );
                };

                $type_simplify->('text') if ( $certain_nodes->{'text'}->@* );

                push( @$node, @leftovers );

                for my $type ( qw( intersection filter ) ) {
                    next unless ( $certain_nodes->{$type}->@* );
                    $type_simplify->($type) if ( $certain_nodes->{$type}->@* );
                }
            }
        } ],
        [ 'pre', 'hash', sub ($node) {
            # block that wraps only a single block removed
            $node->{parts} = $node->{parts}[0]{parts} while (
                $node->{type} and $node->{type} eq 'block' and
                $node->{parts}->@* == 1 and
                $node->{parts}[0]{type} and $node->{parts}[0]{type} eq 'block'
            );
        } ],
    );
}

1;

=head1 NAME

QuizSage::Role::Label::Parse

=head1 SYNOPSIS

    package QuizSage::Model::Label;

    use exact -class;

    with 'QuizSage::Role::Label::Parse';

    sub example ( $self, $label, $user_id = undef ) {
        return $self->parse( $label, $user_id );
    }

=head1 DESCRIPTION

This role provides a label parsing method.

=head1 METHOD

=head2 parse

Parses a label into a data structure. Accepts a string input or otherwise uses
the C<label> data label if the object is model-data-loaded.

    my $label   = QuizSage::Model::Label->new;
    my $data    = $label->parse('Romans 12:1-5 (2) James 1:2-4 (1) NIV ESV*');
    my $data_42 = $label->load(42)->parse;

You can alternatively explicitly pass the user ID.

    my $data = $label->parse( 'Romans 12:1-5 (2) James 1:2-4 (1) NIV ESV*', 42 );

=head1 WITH ROLE

L<QuizSage::Role::Label::Bible>.
