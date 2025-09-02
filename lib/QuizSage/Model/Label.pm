package QuizSage::Model::Label;

use exact -class;
use Bible::Reference;
use Math::Prime::Util 'divisors';
use Mojo::JSON qw( to_json from_json );
use Parse::RecDescent;

with 'Omniframe::Role::Model';

has 'user_id';
has 'user_aliases';

has 'bible_ref' => sub {
    Bible::Reference->new(
        acronyms   => 0,
        sorting    => 1,
        add_detail => 1,
    );
};

has 'bible_acronyms' => sub ($self) {
    return $self->dq('material')->sql(q{
        SELECT acronym FROM bible ORDER BY LENGTH(acronym) DESC, acronym
    })->run->column;
};

has 'bibles' => sub ($self) {
    return $self->dq('material')->sql(q{
        SELECT acronym, label, name, year
        FROM bible
        ORDER BY LENGTH(acronym) DESC, acronym
    })->run->all({});
};

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

sub aliases ( $self, $user_id = $self->user_id ) {
    return $self->dq->get(
        [
            [ [ qw( label l ) ] ],
            [ \q{ LEFT JOIN }, { 'user' => 'u' }, 'user_id' ],
        ],
        [
            'l.*',
            'u.first_name', 'u.last_name', 'u.email',
            'CASE u.user_id WHEN 2 THEN 1 ELSE 0 END AS is_self_made',
        ],
        [
            -bool             => 'l.public',
            maybe 'u.user_id' => $user_id,
        ],
        { order_by => [
            { -desc => { -length => 'l.name' } },
            'l.name',
            'l.public',
            { -desc => 'is_self_made' },
        ] }
    )->run->all({});
}

sub identify_aliases ( $self, $string = '', $user_id = $self->user_id ) {
    return [
        sort { $a cmp $b }
        grep {
            ( my $alias_name = $_ ) =~ s/\s+/\\s+/g;
            $string =~ /\b$alias_name\b/i
        }
        map { $_->{name} }
        $self->aliases->@*
    ];
}

sub __parse ( $self, $input = $self->data->{label}, $user_id = $self->user_id, $aliases = undef ) {
    return {} unless ( defined $input );

    # get aliases
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

    # parse input into a data structure
    my $data = $label_prd_obj->start($input) // {};

    # cleanup nodes of the data structure
    my $nodes;
    $nodes = sub ($node) {
        if ( ref $node eq 'ARRAY' ) {
            $nodes->($_) for (@$node);

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

                # find any text of block nodes after weighted blocks and move them into a weighted block of 1
                for ( 0 .. $#{$node} ) {
                    my $this = $node->[$_];
                    next unless ( $this->{type} and ( $this->{type} eq 'text' or $this->{type} eq 'block' ) );

                    splice( @$node, $_, $#{$node}, {
                        type   => 'weighted_block',
                        weight => 1,
                        parts  => [ @$node[ $_ .. $#{$node} ] ],
                    } );
                    last;
                }

                # remove weight if there's only 1 weighted set of anything that can be weighted in the node
                my @weighted_set_indexes =
                    grep { $node->[$_]{type} and $node->[$_]{type} eq 'weighted_set' }
                    0 .. $#{$node};
                splice( @$node, $weighted_set_indexes[0], 1, $node->[ $weighted_set_indexes[0] ]{parts}->@* )
                    if ( @weighted_set_indexes == 1 );
            }
        }
        elsif ( ref $node eq 'HASH' ) {
            if (
                $node->{type} and (
                    $node->{type} eq 'text' or
                    $node->{type} eq 'filter' or
                    $node->{type} eq 'intersection'
                )
            ) {
                while ( $node->{value} =~ s/([\x{E000}-\x{F8FF}])// ) {
                    if ( my $alias = $tokenized_aliases->[ ord($1) - 57344 ] ) {
                        try {
                            use warnings FATAL => 'recursion';
                            $alias->{value} //= $self->__parse( $alias->{label}, undef, $aliases );
                        }
                        catch ($e) {
                            die "Aliases reference each other to cause deep recursion\n"
                                if ( index( $e, 'Deep recursion ' ) == 0 );
                            die $e;
                        }

                        push( $node->{aliases}->@*, { map { $_ => $alias->{$_} } qw( name label value ) } );
                    }
                }

                # canonicalize refs
                my $refs = $self->bible_ref->clear->simplify(1)->in( delete $node->{value} )->refs;
                $node->{refs} = $refs if ($refs);
            }
            else {
                $nodes->( $node->{$_} ) for ( keys %$node );
            }
        }
    };
    $nodes->($data);

    # TODO: optimize
        # remove sections without data (i.e. text sections with values of nothing, blocks with no parts, etc.)
        # remove outer blocks that have nothing but a single inner block

        # Intersections and filters pulled out and canonicalized
        #     a. All intersection reference sets are merged to a single intersection
        #     b. All filter reference sets are merged to a single filter
        #     c. Canonicalize intersections and filters
        #         i.   Pull out embedded labels
        #         ii.  Reference canonicalize remaining text (no acronyms, sorting, add detail, simplify)
        #         iii. Append sorted embedded labels
        #     d. If there is both an intersection and a filter, the intersection is listed first

    $data->{bibles} = $bibles if ($bibles);
    return $data;
}

sub parse ( $self, $input = $self->data->{label}, $user_id = undef ) {
    my $user_aliases;
    unless ($user_id) {
        $self->user_aliases( $self->aliases ) unless ( $self->user_aliases );
        $user_aliases = $self->user_aliases;
    }
    else {
        $user_aliases = $self->aliases($user_id);
    }

    my $data;
    $input //= '';
    $input =~ s/\r?\n/ /g;
    my @input = ' ' . $input . ' ';

    # Embedded labels identified and tokenized
    for my $alias (
        sort {
            length $b->{name} <=> length $a->{name} ||
            $a->{name} cmp $b->{name} ||
            $a->{public} <=> $b->{public} ||
            $b->{is_self_made} <=> $a->{is_self_made}
        }
        $user_aliases->@*
    ) {
        ( my $re = '\b' . $alias->{name} . '\b' ) =~ s/\s+/\\s+/g;

        @input = map {
            ( ref $_ ) ? $_ : do {
                if ( /$re/i ) {
                    my @parts = map { $_, \$alias->{name} } split( /$re/i );
                    pop @parts if ( @parts > 1 );
                    $data->{aliases}{ $alias->{name} } = $alias->{label};
                    @parts;
                }
                else {
                    $_;
                }
            };
        } @input;
    }

    # Translations pulled out and canonicalized
    #     - Upper-cased, deduplicated, and sorted
    #     - If a single translation is both a primary and auxiliary, the auxiliary is dropped
    if ( my @bible_acronyms = $self->bible_acronyms->@* ) {
        my $bible_re = '\b(?<bible>(?:' . join( '|', @bible_acronyms ) . ')(?:(?:\s*\*+)|\b))';

        for my $input (@input) {
            next if ( ref $input );
            while ( $input =~ s/$bible_re//i ) {
                my $bible = uc $+{bible};
                $data->{bibles}{ ( $bible =~ s/\s*\*+// ) ? 'auxiliary' : 'primary' }{$bible} = 1;
            }
        }
    }

    $data->{bibles}{primary}  = [ sort keys %{ $data->{bibles}{primary} } ];
    $data->{bibles}{auxiliary} = [
        sort
        grep {
            my $bible = $_;
            not grep { $_ eq $bible } $data->{bibles}{primary}->@*;
        }
        keys %{ $data->{bibles}{auxiliary} }
    ];
    delete $data->{bibles}{primary}   unless ( $data->{bibles}{primary}->@*   );
    delete $data->{bibles}{auxiliary} unless ( $data->{bibles}{auxiliary}->@* );
    delete $data->{bibles}            unless ( keys $data->{bibles}->%*       );

    # Add verses notation (i.e. "+1 verse" or "+ 1 V") pulled out and remembered
    my ( $add_verses, $bible_structure );
    for my $input (@input) {
        next if ( not $input or ref $input );
        while ( $input =~ s/\s*\+\s*(\d+)\s*ve?r?s?e?s?//i ) {
            $add_verses = $1 if ( not $add_verses or $1 > $add_verses );
        }
    }
    $bible_structure = {
        map { $_->[0] => $_->[1] } $self->bible_ref->get_bible_structure->@*
    } if ($add_verses);

    # Intersections and filters pulled out and canonicalized
    #     a. All intersection reference sets are merged to a single intersection
    #     b. All filter reference sets are merged to a single filter
    #     c. Canonicalize intersections and filters
    #         i.   Pull out embedded labels
    #         ii.  Reference canonicalize remaining text (no acronyms, sorting, add detail, simplify)
    #         iii. Append sorted embedded labels
    #     d. If there is both an intersection and a filter, the intersection is listed first

    for my $i ( reverse 0 .. @input - 1 ) {
        while ( $input[$i] =~ s/(?<symbol>[~\|])(?<content>[^~\|]*)$// ) {
            push(
                @{ $data->{ ( $+{symbol} eq '~' ) ? 'intersections' : 'filters' } },
                grep { ref $_ or /\S/ } $+{content}, splice( @input, $i + 1 ),
            );
        }
    }
    for my $alter_type ( qw( intersections filters ) ) {
        $data->{$alter_type} = [
            grep { /\S/ }
            join( '; ',
                $self->bible_ref->clear->simplify(1)->in(
                    join( ' ', grep { not ref $_ } $data->{$alter_type}->@* )
                )->refs
            ),
            map { \$_ } sort map { $$_ } grep { ref $_ } $data->{$alter_type}->@*,
        ];
        delete $data->{$alter_type} unless ( $data->{$alter_type}->@* );
    }

    # Range set canonicalized
    #     a. Range set created from splitting remaining text by weight marks
    #     b. Canonicalize range for each range in range set
    #         i.   Pull out embedded labels
    #         ii.  Reference canonicalize remaining text (no acronyms, sorting, add detail, simplify)
    #         iii. Append sorted embedded labels
    #     c. "Lowest common denominator" weights
    #         - If only a single range exist in the set, remove any weight
    #         - If there are multiple ranges in the set, default weight to 1 for any missing weights

    $input[-1] .= ( $input[-1] =~ /\([^\)]*\)/ ) ? ' (1)' : ' ()' if ( $input[-1] !~ /\([^\)]*\)\s*$/ );

    @input = reverse map { ( ref $_ ) ? $_ : scalar reverse $_ } @input;
    for my $i ( reverse 0 .. @input - 1 ) {
        while ( $input[$i] =~ s/(?<remainder>.*)\)(?<weight>[^\(]*)\((?<content>.*)$/$+{remainder}/e ) {
            my @content = (
                grep { ref $_ or /\S/ }
                map { ( ref $_ ) ? $_ : scalar reverse $_ }
                $+{content},
                splice( @input, $i + 1 ),
            );

            ( my $weight = reverse $+{weight} ) =~ s/\D+//g;
            $weight = undef unless ( length $weight );

            my $range = [
                (
                    grep { /\S/ }
                    join( '; ',
                        grep { /\S/ }
                        $self->bible_ref->clear->simplify(1)->in(
                            ($add_verses)
                                ? join( '; ',
                                    map {
                                        /^(?<book>.+)\s(?<chapter>\d+):(?<verse>\d+)$/;
                                        my $ref    = {%+};
                                        my @verses = $_;
                                        my $book   = $bible_structure->{ $+{book} };
                                        for ( 1 .. $add_verses ) {
                                            $ref->{verse}++;
                                            if ( $ref->{verse} > $book->[ $ref->{chapter} - 1 ] ) {
                                                $ref->{chapter}++;
                                                $ref->{verse} = 1;
                                            }
                                            last unless ( $book->[ $ref->{chapter} - 1 ] );
                                            push(
                                                @verses,
                                                $ref->{book} . ' ' . $ref->{chapter} . ':' . $ref->{verse},
                                            );
                                        }
                                        join( '; ', @verses );
                                    }
                                    $self->bible_ref->clear->in(
                                        join( ' ', grep { not ref $_ } @content )
                                    )->as_verses->@*
                                )
                                : join( ' ', grep { not ref $_ } @content )
                        )->refs
                    ),
                ),
                map { \$_ } sort map { $$_ } grep { ref $_ } @content,
            ];

            push(
                @{ $data->{ranges} },
                {
                    maybe range  => $range,
                    maybe weight => $weight,
                },
            ) if (@$range);
        }
    }

    $data->{ranges} = $self->_sort_ranges( $data->{ranges} );

    if ( my @weights = grep { defined } map { $_->{weight} } $data->{ranges}->@* ) {
        my %factors;
        $factors{$_}++ for ( map { divisors($_) } @weights );
        my ($largest_common_factor) = sort { $b <=> $a } grep { $factors{$_} == @weights } keys %factors;
        @weights = map { $_ / $largest_common_factor } @weights;
        $_->{weight} = shift @weights // 1 for ( $data->{ranges}->@* );
    }

    delete $data->{ranges} unless ( $data->{ranges}->@* );

    return $data;
}

sub canonicalize( $self, $input = $self->data->{label}, $user_id = undef ) {
    return $self->format( $self->parse( $input, $user_id ) );
}

sub descriptionize( $self, $input = $self->data->{label}, $user_id = undef ) {
    my $full_data = $self->parse( $input, $user_id );

    # parse data by alias-node, replacing aliases along the way
    try {
        use warnings FATAL => 'recursion';

        my $process_data_node;
        $process_data_node = sub ($data_ref) {
            if ( $$data_ref->{aliases} ) {
                for ( values $$data_ref->{aliases}->%* ) {
                    my $parsed_data = $self->parse($_);
                    $process_data_node->(\$parsed_data);

                    # pull bibles out if they exist
                    my $bibles = delete $parsed_data->{bibles};
                    # if bibles exist in this node but not in the parent node,
                    # move them up to the parent
                    $$data_ref->{bibles} //= $bibles if ($bibles);

                    # replace node's aliases
                    if ( $parsed_data->{aliases} ) {
                        my $replace_aliases = sub ($set) {
                            for my $item (@$set) {
                                $item = $parsed_data->{aliases}{ $$item } if ( ref $item );
                            }
                        };
                        $replace_aliases->( $_->{range} ) for ( $parsed_data->{ranges}->@* );
                        $replace_aliases->( $parsed_data->{$_} ) for ( qw( intersections filters ) );

                        delete $parsed_data->{aliases};
                    }

                    $_ = $parsed_data;
                }
            }
        };
        $process_data_node->(\$full_data);
    }
    catch ($e) {
        die "Aliases reference each other to cause deep recusion\n"
            if ( index( $e, 'Deep recursion ' ) == 0 );
        die $e;
    }

    # replace upper-most node's aliases
    if (
        $full_data->{aliases} and $full_data->{aliases}->%* and
        (
            $full_data->{ranges}        and $full_data->{ranges}->@* or
            $full_data->{intersections} and $full_data->{intersections}->@* or
            $full_data->{filters}       and $full_data->{filters}->@*
        )
    ) {
        my $replace_aliases = sub ($set) {
            for my $item (@$set) {
                $item = $full_data->{aliases}{ $$item } if ( ref $item );
            }
        };
        $replace_aliases->( $_->{range} ) for ( $full_data->{ranges}->@* );
        $replace_aliases->( $full_data->{$_} ) for ( qw( intersections filters ) );

        delete $full_data->{aliases};
    }

    $full_data = from_json to_json $full_data;

    my $child_weight_integrate;
    $child_weight_integrate = sub ($parent) {
        for my $set ( $parent->{ranges}->@* ) {
            for my $item ( $set->{range}->@* ) {
                $child_weight_integrate->($item) if ( ref $item eq 'HASH' );
            }
        }

        my @children = grep { ref $_ eq 'HASH' } map { $_->{range}->@* } $parent->{ranges}->@*;

        if (
            ( $parent->{ranges}->@* == grep { $_->{weight} } $parent->{ranges}->@* ) and
            (
                not grep {
                    grep { ref $_ eq 'HASH' } $_->{range}->@* and
                    grep { not ref $_ } $_->{range}->@*
                } $parent->{ranges}->@*
            ) and
            (
                grep {
                    grep {
                        ref $_ eq 'HASH' and
                        ( $_->{ranges}->@* == grep { $_->{weight} } $_->{ranges}->@* )
                    } $_->{range}->@*
                } $parent->{ranges}->@*
            )
        ) {
            my @sum_weights = map {
                my $sum_weight = 0;
                $sum_weight += $_ for ( map { $_->{weight} } $_->{ranges}->@* );
                $sum_weight;
            } @children;

            my $sums_product = 1;
            $sums_product *= $_ for (@sum_weights);

            $_->{weight} *= $sums_product for ( $parent->{ranges}->@* );

            for ( my $i = 0; $i < @children; $i++ ) {
                $_->{weight} = $_->{weight} / $sum_weights[$i] * $sums_product
                    for ( $children[$i]->{ranges}->@* );
            }

            for ( my $i = 0; $i < $parent->{ranges}->@*; $i++ ) {
                for ( my $j = 0; $j < $parent->{ranges}[$i]{range}->@*; $j++ ) {
                    if ( ref $parent->{ranges}[$i]{range}[$j] eq 'HASH' ) {
                        my $ranges = $parent->{ranges}[$i]{range}[$j]->{ranges};

                        for my $type ( qw( intersections filters ) ) {
                            push( $parent->{filters}->@*, $parent->{ranges}[$i]{range}[$j]->{filters}->@* )
                                if ( ref $parent->{ranges}[$i]{range}[$j]->{filters} eq 'ARRAY' );
                        }

                        splice( $parent->{ranges}->@*, $i, 1, @$ranges );
                    }
                }
            }
        }
        else {
            delete $_->{weight} for ( map { $_->{ranges}->@* } @children );
        }
    };
    $child_weight_integrate->($full_data);

    my $process_data_node;
    $process_data_node = sub ($data_ref) {
        my $replace_ranges = sub ($set) {
            for my $item (@$set) {
                $process_data_node->(\$item) if ( ref $item );
            }
        };
        $replace_ranges->( $_->{range} ) for ( $$data_ref->{ranges}->@* );
        $replace_ranges->( $$data_ref->{$_} ) for ( qw( intersections filters ) );

        if (
            $$data_ref->{ranges} and
            (
                $$data_ref->{intersections} and $$data_ref->{intersections}->@* or
                $$data_ref->{filters}       and $$data_ref->{filters}->@*
            )
        ) {
            my @intersections = ( $$data_ref->{intersections} and $$data_ref->{intersections}->@* )
                ? ( $self->bible_ref->clear->simplify(0)->in(
                    join( '; ', $$data_ref->{intersections}->@* )
                )->as_verses->@* )
                : ();

            my @filters = ( $$data_ref->{filters} and $$data_ref->{filters}->@* )
                ? ( $self->bible_ref->clear->simplify(0)->in(
                    join( '; ', $$data_ref->{filters}->@* )
                )->as_verses->@* )
                : ();

            for ( $$data_ref->{ranges}->@* ) {
                my $verses = $self->bible_ref->clear->simplify(0)->in(
                    join( '; ', $_->{range}->@* )
                )->as_verses;

                $verses = [ grep {
                    my $verse = $_;
                    grep { $verse eq $_ } @intersections;
                } @$verses ] if (@intersections);

                $verses = [ grep {
                    my $verse = $_;
                    not grep { $verse eq $_ } @filters;
                } @$verses ] if (@filters);

                $_->{range} = (@$verses)
                    ? [ $self->bible_ref->clear->simplify(1)->in(
                        join( '; ', @$verses )
                    )->refs ]
                    : undef;
            }

            $$data_ref->{ranges} = [ grep { defined $_->{range} } $$data_ref->{ranges}->@* ];
        }
        delete $$data_ref->{$_} for ( qw( intersections filters ) );

        $$data_ref = $self->format( $$data_ref );
    };
    $process_data_node->(\$full_data);

    return $full_data;
}

sub format( $self, $data ) {
    # Build canonicalized label text
    #     a. Range set
    #     b. Any intersections and filters
    #     c. Any translations

    $data->{ranges} = $self->_sort_ranges( $data->{ranges} );

    my $simplify_refs = sub ($refs) {
        return $self->bible_ref->clear->simplify(1)->in($refs)->refs;
    };

    my $de_set_ify = sub ($set) {
        my @not_refs = grep { not ref $_ } @$set;
        return join( '; ', grep { defined }
            ( (@not_refs) ? $simplify_refs->( join( '; ', @not_refs ) ) : undef ),
            map { $$_ } grep { ref $_ } @$set,
        );
    };

    my %symbols = ( intersections => '~', filters => '|' );

    my $alter_ify = sub ($type) {
        return ( $data->{$type} and $data->{$type}->@* )
            ? $symbols{$type} . ' ' . $de_set_ify->( $data->{$type} )
            : undef;
    };

    return join( ' ',
        grep { defined }
        (
            ( $data->{ranges}->@* > 1 and grep { defined $_->{weight} } $data->{ranges}->@* )
                ? (
                    map {
                        $de_set_ify->( $_->{range} ) . ' (' . ( $_->{weight} // 1 ) . ')'
                    } $data->{ranges}->@*
                )
                : do {
                    my @sets = map { $_->{range}->@* } $data->{ranges}->@*;
                    join( '; ',
                        grep { $_ }
                        $simplify_refs->( join( '; ', grep { not ref $_ } @sets ) ),
                        map { $$_ } grep { ref $_ } @sets,
                    );
                }
        ),
        $alter_ify->('intersections'),
        $alter_ify->('filters'),
        (
            ( $data->{bibles} )
                ? join( ' ',
                    map { $_->[0] . ( ( $_->[1] ) ? '*' : '' )  }
                    sort { $a->[0] cmp $b->[0] }
                    ( map { [ $_, 0 ] } $data->{bibles}{primary  }->@* ),
                    ( map { [ $_, 1 ] } $data->{bibles}{auxiliary}->@* ),
                )
                : undef
        ),
    );
}

sub _sort_ranges ( $self, $ranges ) {
    return [
        sort {
            ref $a->{range}[0] cmp ref $b->{range}[0] or
            (
                ( ref $a->{range}[0] and ref $b->{range}[0] ) ? $a->{range}[0]->$* cmp $b->{range}[0]->$* :
                ( $a->{range}[0] eq $b->{range}[0] ) ? 0 :
                (
                    index(
                        $self->bible_ref->clear->simplify(0)->in(
                            $a->{range}[0] . ' ' . $b->{range}[0]
                        )->as_verses->[0],
                        $self->bible_ref->clear->simplify(0)->in( $a->{range}[0] )->as_verses->[0],
                    ) == 0
                ) ? -1 : 1
            )
        }
        @$ranges
    ];
}

sub fabricate ( $self, $range = undef, $sizes = undef ) {
    $sizes = {
        map { $_ => 1 }
        grep { $_ and $_ > 0 }
        map {
            s/,//;
            0 + ( $_ || 0 );
        }
        split( /[^\d,\.]/, $sizes // '' )
    };
    $sizes = [ sort { $a <=> $b } keys %$sizes ];

    my ( $refs, $lists ) = ( '', [] );
    if ($range) {
        $refs = $self->bible_ref->clear->simplify(1)->in($range)->refs;

        my $sth = $self->dq('material')->sql(q{
            SELECT popularity
            FROM popularity
            JOIN book USING (book_id)
            WHERE
                book.name = ? AND
                popularity.chapter = ? AND
                popularity.verse = ?
        });

        my $verses = [
            sort { $b->[1] <=> $a->[1] }
            map {
                /^(?<book>.+?)\s(?<chapter>\d+):(?<verse>\d+)$/;
                [ $_, $sth->run( $+{book}, $+{chapter}, $+{verse} )->value ];
            }
            $self->bible_ref->clear->simplify(0)->in($range)->as_verses->@*
        ];
        my $total_verses = @$verses;

        for my $size (@$sizes) {
            my $prior_verses_count = ( (@$lists) ? $lists->[-1]{size} : 0 );
            my @new_verses         = splice( @$verses, 0, $size - $prior_verses_count );

            push( @$lists, {
                size => $prior_verses_count + scalar(@new_verses),
                refs => $self->bible_ref->clear
                    ->simplify(1)
                    ->in( join( ';',
                        ( map { $_->{refs} } @$lists ),
                        ( map { $_->[0] } @new_verses ),
                    ) )
                    ->refs,
            } );

            last unless (@$verses);
        }

        push( @$lists => {
            refs => $refs,
            size => $total_verses,
        } ) if (@$verses);
    }

    return $refs, $sizes, $lists;
}

1;

=head1 NAME

QuizSage::Model::Label

=head1 SYNOPSIS

    use QuizSage::Model::Label;

    my $label              = QuizSage::Model::Label->new;
    my $label_with_user_id = QuizSage::Model::Label->new( user_id => 42 );

    my $data        = $label->parse('Romans 12:1-5 (2) James 1:2-4 (1) NIV ESV*');
    my $label_text  = $label->canonicalize('Romans 12:1-5; James 1:2-4');
    my $description = $label->descriptionize('Romans 12:1-5; James 1:2-4');

=head1 DESCRIPTION

This class is the model for material label objects. The primary purpose of this
model is to parse, canonicalize, and descriptionize material labels. A material
label is a string of a restricted syntax optionally with any reference set
therein replaced by a label. See L<Material Labels|docs/material_labels.md>
for additional details.

Labels can be saved to the application database under a name (or "alias"). These
aliases may be private (only seen, edited, and used by the creating user) or
public (viewable and usable by all, but editable only be the creating user).

Any text in a label that's not recognized is ignored, including valid aliases
to which a user doesn't have access.

=head1 ATTRIBUTES

=head2 user_id

Optional user ID used to select private aliases. If not provided, C<aliases>
will only return public aliases.

=head2 user_aliases

A cache of aliases pulled from C<aliases> based on whatever C<user_id> is set to
at the time. This is auto-populated once per object as needed. The data is an
array of hashes.

=head2 bible_ref

The L<Bible::Reference> object used throughout, set with default-correct values.

=head2 bible_acronyms

An auto-populated array of supported Bible translation acronyms.

=head2 bibles

An arrayref of hashrefs containing information about available Bible
translations.

=head1 OBJECT METHODS

=head2 aliases

Returns an array of hashes of aliases based on whatever C<user_id> is set to
at the time.

    my $aliases = $label->aliases;

You can alternatively explicitly pass the user ID.

    my $aliases = $label->aliases(42);

=head2 identify_aliases

Identifies alias names within a string and returns them in alphabetical order in
an arrayref.

    my $identified_aliases = $label->identify_aliases('Alias Name');

=head2 parse

Parses a label into a data structure. Accepts a string input or otherwise uses
the C<label> data label if the object is model-data-loaded.

    my $data    = $label->parse('Romans 12:1-5 (2) James 1:2-4 (1) NIV ESV*');
    my $data_42 = $label->load(42)->parse;

You can alternatively explicitly pass the user ID.

    my $data = $label->parse( 'Romans 12:1-5 (2) James 1:2-4 (1) NIV ESV*', 42 );

=head2 canonicalize

Canonicalize a label, maintaining valid and accessible aliases if any, and
unifying any intersections and/or filters. Accepts a string input or otherwise
uses the C<label> data label if the object is model-data-loaded.

    my $label_text = $label->canonicalize('Romans 12:1-5; James 1:2-4');
    my $label_42   = $label->load(42)->canonicalize;

You can alternatively explicitly pass the user ID.

    my $label_text = $label->canonicalize( 'Romans 12:1-5; James 1:2-4', 42 );

=head2 descriptionize

Convert a label into a description, converting all valid and accessible aliases
to their associated label values, and processing any intersections and/or
filters. Accepts a string input or otherwise uses the C<label> data label if the
object is model-data-loaded. The returned string is suitable for use in
L<QuizSage::Util::Material> calls to generated material JSON.

    my $description    = $label->descriptionize('Romans 12:1-5; James 1:2-4');
    my $description_42 = $label->load(42)->descriptionize;

You can alternatively explicitly pass the user ID.

    my $description = $label->descriptionize( 'Romans 12:1-5; James 1:2-4', 42 );

=head2 format

Return a canonically formatted string given the input of a data structure you
might get from calling C<parse> on a string coming out of C<descriptionize>.

=head2 fabricate

Use the material database's popularity data to fabricate list labels.

=head1 WITH ROLE

L<Omniframe::Role::Model>.

=head1 SEE ALSO

L<Material Labels|docs/material_labels.md>, L<QuizSage::Util::Material>,
L<Bible::Reference>.
