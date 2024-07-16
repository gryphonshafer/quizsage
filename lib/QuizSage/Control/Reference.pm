package QuizSage::Control::Reference;

use exact 'Mojolicious::Controller';
use File::Path 'make_path';
use Mojo::File 'path';
use Omniframe;
use QuizSage::Util::Material 'material_json';
use QuizSage::Util::Reference 'reference_data';

class_has conf => Omniframe->with_roles('+Conf')->new->conf;

sub lookup ($self) {
    return $self->redirect_to('/') unless ( -f join( '/',
        $self->conf->get( qw( config_app root_dir ) ),
        $self->conf->get( qw( material json location ) ),
        $self->stash('material_json_id') . '.json',
    ) );

    $self->stash( js_app => Omniframe->with_roles('QuizSage::Role::JSApp')->new );
}

sub generator ($self) {
    my $reference_data = reference_data(
        user_id => $self->stash('user')->id,
        $self->stash('user')->{data}{settings}{ref_gen}->%*,
    );

    # remove any reference HTML files that haven't been accessed in the last N days
    my $now        = time;
    my $atime_life = $self->conf->get( qw{ reference atime_life } );
    my $html_path  = path( join( '/',
        $self->conf->get( qw{ config_app root_dir } ),
        $self->conf->get( qw{ reference location html } ),
    ) );

    $html_path->list->grep( sub ($file) {
        ( $now - $file->stat->atime ) / ( 60 * 60 * 24 ) > $atime_life
    } )->each('remove');

    my $html_file = $html_path->child( $reference_data->{id} . '.html' );

    my $html;
    unless ( -f $html_file ) {
        $html = $self->app->tt_html(
            $self->stash('controller') . '/' . $self->stash('action') . '.html.tt',
            {
                page => {
                    no_defaults => 1,
                    lang        => 'en',
                    charset     => 'utf-8',
                    viewport    => 1,
                },
                $reference_data->%*,
            },
        );

        make_path( $html_file->dirname ) unless ( -d $html_file->dirname );
        $html_file->spew($html);
    }
    else {
        $html = $html_file->slurp;
    }

    $self->stash( skip_packer => 1 );
    $self->render( text => $html );
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
