package Label_v2;

use exact -class, -fun;
use Bible::Reference;

with 'Omniframe::Role::Model';

has 'user_id';
has 'user_aliases';

has 'bible_ref' => sub {
    return Bible::Reference->new(
        acronyms   => 0,
        sorting    => 1,
        add_detail => 1,
    );
};

has 'bible_acronyms' => sub ($self) {
    return [ qw( NIV84 ESV NIV ) ];
};

method aliases ( $user_id = $self->user_id ) {
    return [
        {
            name  => 'Club (100)',
            label => 'Rom 1:1-10',
        },
        {
            name  => 'Club [200]',
            label => 'Rom 1:1-20',
        },
        {
            name  => 'Club <300>',
            label => 'Rom 1:1-30',
        },
    ];
}

method parse ( $input = $self->data->{label} // '', $user_id = undef ) {
    my $context = $self->_parse_context_setup( $input, $user_id );
    say '> ' . _untoken( $context->{input_ref}->$* );

    _tokenize_any_aliases($context);
    say '> ' . _untoken( $context->{input_ref}->$* );

    _store_off_any_bibles($context);
    say '> ' . _untoken( $context->{input_ref}->$* );

    _tokenize_any_explicit_blocks($context);
    say '> ' . _untoken( $context->{input_ref}->$* );

    _store_off_any_trailing_filters_intersections_and_additions($context);
    say '> ' . _untoken( $context->{input_ref}->$* );

    _store_off_any_distributives($context);
    say '> ' . _untoken( $context->{input_ref}->$* );

    _store_off_any_trailing_filters_intersections_and_additions($context);
    say '> ' . _untoken( $context->{input_ref}->$* );

    _store_off_weighted_blocks($context);
    say '> ' . _untoken( $context->{input_ref}->$* );

    _store_off_remainder_as_an_implicit_weighted_block_or_unweighted_block($context);
    say '> ' . _untoken( $context->{input_ref}->$* );
}

method _parse_context_setup ( $input, $user_id ) {
    return {
        input_ref      => \ _despace( _detoken($input) ),
        bible_acronyms => $self->bible_acronyms,
        aliases        => (
            ($user_id)
                ? do {
                    $self->user_aliases( $self->aliases ) unless ( $self->user_aliases );
                    $self->user_aliases;
                }
                : $self->aliases($user_id)
        ),
    };
}

sub _tokenize_any_aliases ($context) {
    for my $alias ( $context->{aliases}->@* ) {
        ( my $re = quotemeta( $alias->{name} ) ) =~ s/\s+/\\s+/g;
        _tokenize(
            context => $context,
            name    => $alias->{name},
            value   => {
                type => 'alias',
                value => $alias,
            },
        );
    }
    return;
}

sub _store_off_any_bibles ($context) {
    if ( $context->{bible_acronyms}->@* ) {
        my $bible_re = '\b(?<bible>(?:' . join( '|', $context->{bible_acronyms}->@* ) . ')(?:(?:\s*\*+)|\b))';
        while ( $context->{input_ref}->$* =~ s/$bible_re//i ) {
            my $bible = uc $+{bible};
            $context->{bibles}{ ( $bible =~ s/\s*\*+// ) ? 'auxiliary' : 'primary' }{$bible} = 1;
        }
    }
    return;
}

sub _tokenize_any_explicit_blocks ($context) {
    0 while (
        _tokenize(
            context => $context,
            regex   => '\[([^\[\]]+)\]',
            value   => sub {
                return {
                    type  => 'block',
                    value => _despace( _untoken( $_[0] ) ),
                };
            },
        )
    );
    return;
}

sub _store_off_any_trailing_filters_intersections_and_additions ($context) {
    while (
        $context->{input_ref}->$* =~ s/
            (?:
                (~)
                \s*
                ([^~\|\+\(\)]+)
            $)
            |
            (?:
                (\|)
                \s*
                ([^~\|\+\(\)]+)
            $)
            |
            (?:
                (\+)
                \s*
                (\d+)
                [^~\|\+\(\)]*
            $)
        //x
    ) {
        my ( $symbol, $value ) = grep { defined } map { eval "\$$_" } 1..$#+;
        push( $context->{trailing_fia}->@*, {
            type => (
                ( $symbol eq '~' ) ? 'intersection' :
                ( $symbol eq '|' ) ? 'filter'       :
                ( $symbol eq '+' ) ? 'addition'     : 'unknown'
            ),
            value => _despace( _untoken($value) ),
        } );
    }
    return;
}

sub _store_off_any_distributives ($context) {
    unshift( $context->{distributives}->@*, _despace( _untoken($1) ) )
        while ( $context->{input_ref}->$* =~ s/\/\s*([\w\x{E000}-\x{F8FF}][^\/]*)$// );
    return;
}

sub _store_off_weighted_blocks ($context) {
    push( $context->{weighted_blocks}->@*, {
        type   => 'weight',
        weight => $+{weight},
        text   => _despace( _untoken( $+{text} ) ),
    } ) while ( $context->{input_ref}->$* =~ s/(?<text>[\w\x{E000}-\x{F8FF}][^\)]+)\((?<weight>[^\)]+)\)// );
    return;
}

sub _store_off_remainder_as_an_implicit_weighted_block_or_unweighted_block ($context) {
    if ( $context->{input_ref}->$* ) {
        if ( $context->{weighted_blocks} and $context->{weighted_blocks}->@* ) {
            push( $context->{weighted_blocks}->@*, $context->{input_ref}->$* . ' (1)' );
        }
        else {
            $context->{unweighted_block} = $context->{input_ref}->$*;
        }
        $context->{input_ref}->$* = '';
    }
    return;
}

fun _tokenize (
    :$context,
    :$name  = undef,
    :$regex = undef,
    :$value,
) {
    my $chr = chr( 57344 + @{ $context->{tokens} // [] } );
    $regex //= quotemeta($name);
    my $matches = ($name)
        ? $context->{input_ref}->$* =~ s/$regex/$chr/gi
        : $context->{input_ref}->$* =~ s/$regex/$chr/i;
    return unless $matches;
    $value = $value->( map { eval "\$$_" } 1..$#+ ) if ( ref $value eq 'CODE' );
    push( @{ $context->{tokens} }, $value );
    return $matches;
}

sub _despace ( $string = '' ) {
    $string =~ s/\s+/ /g;
    $string =~ s/(?:^\s+|\s+$)//g;
    return $string;
}

sub _detoken ( $string = '' ) {
    $string =~ /[\x{E000}-\x{F8FF}]/;
    return $string;
}

sub _untoken ( $string = '' ) {
    $string =~ s/([\x{E000}-\x{F8FF}])/ sprintf( "\\x{%04X}", ord($1) ) /ge;
    return $string;
}

1;
