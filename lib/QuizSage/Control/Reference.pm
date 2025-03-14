package QuizSage::Control::Reference;

use exact -conf, 'Mojolicious::Controller';
use File::Path 'make_path';
use Mojo::File 'path';
use Omniframe;
use QuizSage::Util::Material 'material_json';
use QuizSage::Util::Reference qw( reference_data reference_html );

sub lookup ($self) {
    return $self->redirect_to('/') unless ( -f join( '/',
        conf->get( qw( config_app root_dir ) ),
        conf->get( qw( material json location ) ),
        $self->stash('material_json_id') . '.json',
    ) );

    $self->stash( js_app => Omniframe->with_roles('QuizSage::Role::JSApp')->new );
}

sub generator ($self) {
    $self->stash( skip_packer => 1 );

    try {
        $self->render( text => reference_html(
            $self,
            reference_data(
                user_id => $self->stash('user')->id,
                $self->stash('user')->data->{settings}{ref_gen}->%*,
            ),
        ) );
    }
    catch ($e) {
        $self->notice( deat $e );
        $self->flash( memo => { class   => 'error', message => deat $e } );
        return $self->redirect_to('/reference/generator/setup');
    }
}

1;

=head1 NAME

QuizSage::Control::Reference

=head1 DESCRIPTION

This class is a subclass of L<Mojolicious::Controller> and provides handlers
for "Reference" actions.

=head1 METHODS

=head2 lookup

This controller handles material and thesaurus lookup display.

=head2 generator

This controller handles material content document generation.

=head1 INHERITANCE

L<Mojolicious::Controller>.
