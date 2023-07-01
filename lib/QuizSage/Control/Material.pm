package QuizSage::Control::Material;

use exact -conf, 'Mojolicious::Controller';
use Mojo::File 'path';
use QuizSage::Util::Material qw( material_json label2path path2label );

sub json ($self) {
    my $label = path2label( $self->stash('label') );

    my $results;
    try {
        $results = material_json($label);
    }
    catch ($e) {
        $e =~ s/\s+at\s+(?:(?!\s+at\s+).)*[\r\n]*$//;
        return $self->render( json => { error => $e } );
    }

    return $self->redirect_to( label2path( $results->{label} ) ) if ( $label ne $results->{label} );
    $self->render( text => path( conf->get( qw( config_app root_dir ) ) . '/' . $results->{output} )->slurp );
}

1;

=head1 NAME

QuizSage::Control::Material

=head1 DESCRIPTION

This class is a subclass of L<Mojolicious::Controller> and provides handlers
for "Material" actions.

=head1 METHODS

=head2 json

Handler for material JSON.

=head1 INHERITANCE

L<Mojolicious::Controller>.
