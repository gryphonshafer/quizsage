package QuizSage::Model::Season;

use exact -class;
use Mojo::JSON qw( encode_json decode_json );
use YAML::XS 'LoadFile';

with qw( Omniframe::Role::Model Omniframe::Role::Time );

sub validate ( $self, $data ) {
    if ( $data->{start} ) {
        my $dt = $self->time->parse( $data->{start}, 'local' );
        $data->{start} =
            $dt->strftime( $self->time->formats->{ansi} ) .
            $self->time->format_offset( $dt->offset );
    }

    $data->{settings} = LoadFile(
        $self->conf->get( qw( config_app root_dir ) ) . '/config/defaults/season.yaml'
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
