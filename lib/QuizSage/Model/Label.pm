package QuizSage::Model::Label;

use exact -class;
use Bible::Reference;
use Math::Prime::Util 'divisors';
use Mojo::JSON qw( encode_json decode_json );

with 'Omniframe::Role::Model';

has 'user_id';
has 'user_aliases';

has 'bible_ref' => Bible::Reference->new(
    acronyms   => 0,
    sorting    => 1,
    add_detail => 1,
);

has 'bible_acronyms' => sub ($self) {
    return $self->dq('material')->sql(q{
        SELECT acronym FROM bible ORDER BY LENGTH(acronym) DESC, acronym
    })->run->column;
};

sub aliases ($self) {
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
            maybe 'u.user_id' => $self->user_id,
        ],
        { order_by => [
            { -desc => { -length => 'l.name' } },
            'l.name',
            'l.public',
            { -desc => 'is_self_made' },
        ] }
    )->run->all({});
}

sub parse ( $self, $input = $self->data->{label} ) {
    $self->user_aliases( $self->aliases ) unless ( $self->user_aliases );

    my $data;
    my @input = ' ' . $input . ' ';

    # Embedded labels identified and tokenized
    for my $alias (
        sort {
            length $b->{name} <=> length $a->{name} ||
            $a->{name} cmp $b->{name} ||
            $a->{public} <=> $b->{public} ||
            $b->{is_self_made} <=> $a->{is_self_made}
        }
        $self->user_aliases->@*
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

    my $bible_re = '\b(?<bible>(?:' . join( '|', $self->bible_acronyms->@* ) . ')(?:(?:\s*\*+)|\b))';

    for my $input (@input) {
        next if ( ref $input );
        while ( $input =~ s/$bible_re//i ) {
            my $bible = uc $+{bible};
            $data->{bibles}{ ( $bible =~ s/\s*\*+// ) ? 'auxiliary' : 'primary' }{$bible} = 1;
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
                            join( ' ', grep { not ref $_ } @content )
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

sub canonicalize( $self, $input = $self->data->{label} ) {
    return $self->format( $self->parse($input) );
}

sub descriptionize( $self, $input = $self->data->{label} ) {
    my $full_data = $self->parse($input);

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

    $full_data = decode_json encode_json $full_data;

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
model is to parse, caonicalize, and descriptionize material labels. A material
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

=head1 OBJECT METHODS

=head2 aliases

Returns an array of hashes of aliases based on whatever C<user_id> is set to
at the time.

    my $aliases = $label->aliases;

=head2 parse

Parses a label into a data structure. Accepts a string input or otherwise uses
the C<label> data label if the object is model-data-loaded.

    my $data    = $label->parse('Romans 12:1-5 (2) James 1:2-4 (1) NIV ESV*');
    my $data_42 = $label->load(42)->parse;

=head2 canonicalize

Canonicalize a label, maintaining valid and accessible aliases if any, and
unifying any intersections and/or filters. Accepts a string input or otherwise
uses the C<label> data label if the object is model-data-loaded.

    my $label_text = $label->canonicalize('Romans 12:1-5; James 1:2-4');
    my $label_42   = $label->load(42)->canonicalize;

=head2 descriptionize

Convert a label into a description, converting all valid and accessible aliases
to their associated label values, and processing any intersections and/or
filters. Accepts a string input or otherwise uses the C<label> data label if the
object is model-data-loaded. The returned string is suitable for use in
L<QuizSage::Util::Material> calls to generated material JSON.

    my $description    = $label->descriptionize('Romans 12:1-5; James 1:2-4');
    my $description_42 = $label->load(42)->descriptionize;

=head2 format

Return a canonically formatted string given the input of a data structure you
might get from calling C<parse> on a string coming out of C<descriptionize>.

=head1 WITH ROLE

L<Omniframe::Role::Model>.

=head1 SEE ALSO

L<Material Labels|docs/material_labels.md>, L<QuizSage::Util::Material>,
L<Bible::Reference>.
