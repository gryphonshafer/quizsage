package QuizSage::Model::Season;

use exact -class;
use Mojo::JSON qw( encode_json decode_json );
use QuizSage::Model::Meet;

with qw( Omniframe::Role::Model Omniframe::Role::Time QuizSage::Role::Data );

before 'create' => sub ( $self, $params ) {
    $params->{settings} //= $self->dataload('config/meets/defaults/season.yaml');
};

sub freeze ( $self, $data ) {
    $data->{start} = $self->time->parse( $data->{start} )->format('sqlite_min')
        if ( $self->is_dirty( 'start', $data ) );

    $data->{settings} = encode_json( $data->{settings} );
    undef $data->{settings} if ( $data->{settings} eq '{}' or $data->{settings} eq 'null' );

    return $data;
}

sub thaw ( $self, $data ) {
    $data->{settings} = ( defined $data->{settings} ) ? decode_json( $data->{settings} ) : {};
    return $data;
}

sub active_seasons ($self) {
    return [
        map {
            $_->{meets} = [
                map {
                    $_->{start} = $self->time
                        ->parse( $_->{start} )
                        ->format('%a, %b %e, %Y at %l:%M %p %Z');
                    $_;
                }
                $self->dq->get(
                    'meet',
                    [
                        qw( meet_id name location ),
                        [ \q{ STRFTIME( '%s', start ) } => 'start' ],
                    ],
                    { $self->id_name => $_->{season_id} },
                    { order_by => 'start' },
                )->run->all({})->@*
            ];
            $_;
        } $self->dq->get(
            $self->name,
            [ qw( season_id name location ) ],
            \q{
                STRFTIME( '%s', 'NOW' )
                    BETWEEN
                        STRFTIME( '%s', start )
                    AND
                        STRFTIME( '%s', start, days || ' days' )
            },
            { order_by => [ 'location', 'name' ] },
        )->run->all({})->@*
    ];
}

1;

=head1 NAME

QuizSage::Model::Season

=head1 SYNOPSIS

    use QuizSage::Model::Season;

    my $quiz = QuizSage::Model::Season->new;

=head1 DESCRIPTION

This class is the model for season objects.

=head1 OBJECT METHODS

=head2 validate, freeze, thaw

=head2 active_seasons

=head1 WITH ROLES

L<Omniframe::Role::Model>, L<Omniframe::Role::Time>, L<QuizSage::Role::Data>.
