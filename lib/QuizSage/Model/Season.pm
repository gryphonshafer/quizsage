package QuizSage::Model::Season;

use exact -class;
use Mojo::JSON qw( encode_json decode_json );
use QuizSage::Model::Meet;
use YAML::XS 'LoadFile';

with qw( Omniframe::Role::Model Omniframe::Role::Time );

sub validate ( $self, $data ) {
    if ( $data->{start} ) {
        my $dt = $self->time->parse( $data->{start}, delete $data->{start_olson} || 'local' );
        $data->{start} =
            $dt->strftime('%Y-%m-%d %H:%M') .
            $self->time->format_offset( $dt->offset );
    }

    $data->{settings} = LoadFile(
        $self->conf->get( qw( config_app root_dir ) ) . '/config/meets/defaults/season.yaml'
    ) unless ( defined $data->{settings} );

    return $data;
};

sub freeze ( $self, $data ) {
    $data->{settings} = encode_json( $data->{settings} ) if ( defined $data->{settings} );
    return $data;
}

sub thaw ( $self, $data ) {
    $data->{settings} = decode_json( $data->{settings} ) if ( defined $data->{settings} );
    return $data;
}

sub active_seasons ( $self, $olson = 'America/Los_Angeles' ) {
    return [
        map {
            $_->{meets} = [
                map {
                    $_->{start} = $self->time
                        ->parse( $_->{start}, $olson )
                        ->strftime('%a, %b %e, %Y at %l:%M %p');
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

=head1 WITH ROLE

L<Omniframe::Role::Model>, L<Omniframe::Role::Time>.
