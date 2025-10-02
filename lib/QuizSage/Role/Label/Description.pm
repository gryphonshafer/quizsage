package QuizSage::Role::Label::Description;

use exact -role;
use Omniframe::Util::Data qw( deepcopy node_descend );

with 'QuizSage::Role::Label::Bible';

sub descriptionate( $self, $parse ) {
    $parse = deepcopy $parse;
    return if (
        not $parse or
        not $parse->{parts} or
        ( ref $parse->{parts} eq 'HASH' and exists $parse->{parts}{error} )
    );

    my $ranges = [ map {
        ( ref $_ eq 'HASH' and $_->{weight} )
            ? {
                range  => $_->{value},
                weight => $_->{weight},
            } :
        ( ref $_ eq 'HASH' and $_->{elements} )
            ? ( $_->{elements}->@* )
            : { range  => $_ }
    } node_descend(
        $parse->{parts},
        [ 'post', 'hash', sub ($node) {
            if ( $node->{type} ) {
                if (
                    $node->{type} eq 'text' or
                    $node->{type} eq 'filter' or
                    $node->{type} eq 'intersection'
                ) {
                    %$node = (
                        type          => $node->{type},
                        maybe special => $node->{special},
                        maybe value   => join( '; ', grep { defined }
                            $node->{refs},
                            map { $_->{parts}->@* } @{ $node->{aliases} // [] },
                        ) || undef,
                    );
                }
                elsif ( $node->{type} eq 'distributive' ) {
                    for ( $node->{prefix}->@*, $node->{suffix}->@* ) {
                        $_ = {
                            value  => $_,
                            weight => 1,
                        } if ( not ref $_ );
                    }

                    my $all = join( '; ', map { $_->{value} } $node->{prefix}->@* );

                    %$node = ( elements => [ map {
                        my $suffix = $_;

                        grep { $_->{range} }
                        map {
                            my $prefix = $_;

                            my %verses;
                            $verses{$_}++ for (
                                map { $self->versify_refs($_)->@* } (
                                    $prefix->{value},
                                    (
                                        ( ref $suffix->{value} and $suffix->{value}{special} eq 'All' )
                                            ? $all
                                            : $suffix->{value}
                                    ),
                                )
                            );
                            %verses = map { $_ => 1 } grep { $verses{$_} > 1 } keys %verses;

                            +{
                                weight => ( $prefix->{weight} // 1 ) * ( $suffix->{weight} // 1 ),
                                range  => $self->canonicalize_refs( keys %verses ),
                            };
                        } $node->{prefix}->@*;
                    } $node->{suffix}->@* ] );
                }

                if ( $node->{parts} and $node->{parts}->@* == 1 ) {
                    $node->{type} = 'text' if ( $node->{type} eq 'block' );
                    ( $node->{value} ) = ( delete $node->{parts} )->@*;
                }
            }
        } ],
        [ 'post', 'array', sub ($node) {
            # while node array contains a block/weighted_set and a not-block/weighted_set,
            # find the first not-block/weighted_set and
            # distribute it into all preceding blocks/weighted_sets
            my $de_block_needed = 0;
            while (1) {
                my @blocks_ids;
                my $not_block;

                for my $i ( 0 .. @$node - 1 ) {
                    if ( ref $node->[$i] eq 'HASH' and $node->[$i]{type} and $node->[$i]{type} eq 'block' ) {
                        push( @blocks_ids, $i );
                    }
                    elsif (@blocks_ids) {
                        $not_block = splice( @$node, $i, 1 );
                        last;
                    }
                }

                last unless ( @blocks_ids and $not_block );

                for my $i (@blocks_ids) {
                    for my $part ( $node->[$i]{parts}->@* ) {
                        ( $part->{value} ) = $self->_descriptionize_array_node( [
                            { type => 'text', value => $part->{value} },
                            $not_block,
                        ] )->@*;
                    }
                }
                $de_block_needed = 1;
            }

            while ($de_block_needed) {
                $de_block_needed = 0;
                for my $i ( 0 .. @$node - 1 ) {
                    if ( ref $node->[$i] eq 'HASH' and $node->[$i]{type} and $node->[$i]{type} eq 'block' ) {
                        splice( @$node, $i, 1, $node->[$i]{parts}->@* );
                        $de_block_needed = 1;
                        last;
                    }
                }
            }

            # process the broader array
            $self->_descriptionize_array_node($node);
        } ],
    )->@* ];

    my $bibles;
    if ( exists $parse->{bibles} ) {
        push( @$bibles, sort $parse->{bibles}{primary}->@* ) if ( exists $parse->{bibles}{primary} );
        push( @$bibles, map { $_ . '*' } sort $parse->{bibles}{auxiliary}->@* )
            if ( exists $parse->{bibles}{auxiliary} );
    }
    $bibles = join( ' ', @$bibles ) if ( $bibles and @$bibles );

    my $description = join( ' ',
        (
            map {
                $_->{range} .
                    ( ( $_->{weight} ) ? ' (' . $_->{weight} . ')' : '' );
            } @$ranges
        ),
        grep { defined } $bibles,
    );

    return if ( not $description or $description =~ /(?:HASH|ARRAY)\(0x[0-9a-f]+\)/ );

    return ( not wantarray ) ? $description : (
        $description,
        {
            ranges       => $ranges,
            maybe bibles => $parse->{bibles},
        },
    );
}

sub _descriptionize_array_node ( $self, $node ) {
    my $verses = {};

    my @sets = map {
        my $set = $_;
        $set->{verses}{$_} = 1 for ( $self->versify_refs( $set->{value} )->@* );
        $set;
    } grep { $_->{type} and $_->{type} eq 'weighted_set' } @$node;

    my @not_sets = grep { not ( $_->{type} and $_->{type} eq 'weighted_set' ) } @$node;

    return $node unless (@not_sets);

    my $merge = sub ($code) {
        unless (@sets) {
            $code->($verses);
        }
        else {
            $code->( $_->{verses} ) for (@sets);
        }
    };

    for my $bit (@not_sets) {
        if ( $bit->{type} ) {
            if ( $bit->{value} ) {
                my $versified_refs = $self->versify_refs( $bit->{value} );

                if ( $bit->{type} eq 'text' ) {
                    $merge->( sub ($target) { $target->{$_} = 1 for ( $versified_refs->@* ) } );
                }
                elsif ( $bit->{type} eq 'filter' ) {
                    $merge->( sub ($target) { delete $target->{$_} for ( $versified_refs->@* ) } );
                }
                elsif ( $bit->{type} eq 'intersection' ) {
                    $merge->( sub ($target) {
                        $target->{$_}++ for ( $versified_refs->@* );
                        %$target = map { $_ => 1 } grep { $target->{$_} > 1 } keys %$target;
                    } );
                }
            }
            elsif ( $bit->{type} eq 'addition' ) {
                $merge->( sub ($target) {
                    %$target =
                        map {
                            /^(?<book>.+)\s(?<chapter>\d+):(?<verse>\d+)$/;
                            my $ref    = {%+};
                            my @verses = $_;
                            my $book   = $self->bible_structure->{ $+{book} };
                            for ( 1 .. $bit->{amount} ) {
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
                            map { $_ => 1 } @verses;
                        }
                        keys %$target;
                } );
            }
        }
    }

    unless (@sets) {
        @$node = $self->canonicalize_refs( keys %$verses ) if (%$verses);
    }
    else {
        @$node =
            grep { defined }
            map {
                my $set = $_;
                my $verses = delete $set->{verses};
                $set->{value} = $self->canonicalize_refs( keys %$verses );
                ( $set->{value} ) ? $set : undef;
            } @sets;
    }

    return $node;
}

1;

=head1 NAME

QuizSage::Role::Label::Description

=head1 SYNOPSIS

    package QuizSage::Model::Label;

    use exact -class;

    with 'QuizSage::Role::Label::Description';

    sub example ( $self, $parsed_label_data ) {
        return $self->descriptionate($parsed_label_data);
    }

=head1 DESCRIPTION

This role provides the label descriptionate method.

=head1 METHOD

=head2 descriptionate

Convert parsed label data into a description string, converting all valid and
accessible aliases to their associated label values, and processing any
intersections and/or filters and other label elements.

    my $label       = QuizSage::Model::Label->new;
    my $description = $label->descriptionate($parsed_label_data);

=head1 WITH ROLE

L<QuizSage::Role::Label::Bible>.
