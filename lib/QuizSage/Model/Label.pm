package QuizSage::Model::Label;

use exact -class;
use Omniframe::Util::Data qw( deepcopy node_descend );

with qw(
    Omniframe::Role::Model
    QuizSage::Role::Label::Bible
    QuizSage::Role::Label::Description
    QuizSage::Role::Label::Parse
);

has 'user_id';

sub aliases ( $self, $user_id = $self->user_id, $internal_sort = undef ) {
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
            {
                -desc => ($internal_sort)
                    ? { -length => 'l.name' }
                    : \'FLOOR( JULIANDAY( l.created ) / 365.25 * 9 )'
            },
            'l.name',
            'l.public',
            { -desc => 'is_self_made' },
        ] }
    )->run->all({});
}

sub identify_aliases (
    $self,
    $string  = '',
    $user_id = $self->user_id,
) {
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

sub format ( $self, $parse ) {
    $parse = deepcopy $parse;
    return if (
        not $parse or
        not $parse->{parts} or
        ( ref $parse->{parts} eq 'HASH' and exists $parse->{parts}{error} )
    );

    return join( ' ',
        node_descend(
            $parse->{parts},
            [ 'pre', 'hash', sub ($node) {
                if ( $node->{type} ) {
                    if (
                        $node->{type} eq 'text' or
                        $node->{type} eq 'filter' or
                        $node->{type} eq 'intersection'
                    ) {
                        %$node = (
                            value => join( ' ', grep { defined }
                                (
                                    ( $node->{type} eq 'filter'       ) ? '|' :
                                    ( $node->{type} eq 'intersection' ) ? '~' : undef
                                ),
                                join( '; ', grep { defined }
                                    ( $node->{refs}    // undef ),
                                    ( $node->{special} // undef ),
                                    map { $_->{name} } $node->{aliases}->@*,
                                ),
                            )
                        );
                    }
                    elsif ( $node->{type} eq 'addition' ) {
                        %$node = ( value => '+' . $node->{amount} );
                    }
                }
            } ],
            [ 'post', 'hash', sub ($node) {
                if ( $node->{type} ) {
                    if ( $node->{type} eq 'weighted_set' and not grep { ref $_ } $node->{parts}->@* ) {
                        %$node = ( value => join( ' ',
                            $node->{parts}->@*, '(' . $node->{weight} . ')',
                        ) );
                    }
                    elsif ( $node->{type} eq 'block' and not grep { ref $_ } $node->{parts}->@* ) {
                        %$node = ( value => join( ' ', '[', $node->{parts}->@*, ']' ) );
                    }
                    elsif (
                        $node->{type} eq 'distributive'
                        and not grep { ref $_ } $node->{prefix}->@*
                        and not grep { ref $_ } $node->{suffix}->@*
                    ) {
                        %$node = ( value => join( ' ',
                            $node->{prefix}->@*, '/', $node->{suffix}->@*
                        ) );
                    }
                }
            } ],
            [ 'post', 'array', sub ($node) {
                @$node = map { $_->{value} } grep { ref $_ eq 'HASH' and defined $_->{value} } @$node;
            } ],
        )->@*,
        ( sort @{ $parse->{bibles}{primary} // [] } ),
        ( map { $_ . '*' } sort @{ $parse->{bibles}{auxiliary} // [] } ),
    );
}

sub canonicalize( $self, $input = $self->data->{label}, $user_id = undef ) {
    return $self->format( $self->parse( $input, $user_id ) );
}

sub descriptionize( $self, $input = $self->data->{label}, $user_id = $self->user_id ) {
    return scalar $self->descriptionate( $self->parse( $input, $user_id ) );
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
            $self->versify_refs($range)->@*
        ];
        my $total_verses = @$verses;

        for my $size (@$sizes) {
            my $prior_verses_count = ( (@$lists) ? $lists->[-1]{size} : 0 );
            my @new_verses         = splice( @$verses, 0, $size - $prior_verses_count );

            push( @$lists, {
                size => $prior_verses_count + scalar(@new_verses),
                refs => $self->canonicalize_refs(
                    ( map { $_->{refs} } @$lists ),
                    ( map { $_->[0] } @new_verses ),
                ),
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

sub is_multi_chapter ( $self, $label = undef ) {
    $label //= $self->data->{label};
    try {
        my ( $description, $structure ) = $self->descriptionate( $self->parse($label) );
        die unless ( $structure and ref $structure eq 'HASH' and ref $structure->{ranges} eq 'ARRAY' );
        return ( $self->chapterify_refs( map { $_->{range} } $structure->{ranges}->@* )->@* > 1 ) ? 1 : 0;
    }
    catch ($e) {
        return 0;
    }
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

=head1 ATTRIBUTE

=head2 user_id

Optional user ID used to select private aliases. If not provided, C<aliases>
will only return public aliases.

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

=head2 format

Return a canonically formatted string given the input of a data structure you
might get from calling C<parse> on a string coming out of C<descriptionize>.

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

=head2 fabricate

Use the material database's popularity data to fabricate list labels.

=head2 is_multi_chapter

Given a label string as input (or if not provided, will try to use a loaded
object's C<label> data value), this method will return 1 or 0 indicating the
label contains multiple chapters (versus 1 or none).

=head1 WITH ROLE

L<Omniframe::Role::Model>, L<QuizSage::Role::Label::Bible>,
L<QuizSage::Role::Label::Description>, L<QuizSage::Role::Label::Parse>.

=head1 SEE ALSO

L<Material Labels|docs/material_labels.md>, L<QuizSage::Util::Material>.
