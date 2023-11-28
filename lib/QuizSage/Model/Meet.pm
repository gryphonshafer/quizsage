package QuizSage::Model::Meet;

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
        $self->conf->get( qw( config_app root_dir ) ) . '/config/defaults/meet.yaml'
    ) unless ( defined $data->{settings} );

    return $data;
};

sub freeze ( $self, $data ) {
    for ( qw( settings state ) ) {
        $data->{$_} = encode_json( $data->{$_} ) if ( defined $data->{$_} );
    }
    return $data;
}

sub thaw ( $self, $data ) {
    for ( qw( settings state ) ) {
        $data->{$_} = decode_json( $data->{$_} ) if ( defined $data->{$_} );
    }
    return $data;
}

sub build {
    # TODO

    return;
}

sub unbuild ($self) {
    $self->dq->sql('DELETE FROM quiz WHERE meet_id = ?')->run( $self->id );
    return;
}

sub rebuild ($self) {
    $self->unbuild;
    $self->build;
    return;
}

1;

=head1 NAME

QuizSage::Model::Meet

=head1 SYNOPSIS

    use QuizSage::Model::Meet;

    my $quiz = QuizSage::Model::Meet->new;

=head1 DESCRIPTION

This class is the model for meet objects.

=head1 OBJECT METHODS

=head2 validate, freeze, thaw

=head1 WITH ROLE

L<Omniframe::Role::Model>, L<Omniframe::Role::Time>.
