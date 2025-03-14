package QuizSage::Control::Api::Material;

use exact 'Mojolicious::Controller';
use Mojo::File 'path';
use Mojo::JSON 'decode_json';
use QuizSage::Model::Label;
use QuizSage::Util::Material 'material_json';
use QuizSage::Util::Reference qw( reference_data reference_html );

my $label = QuizSage::Model::Label->new;

sub bibles ($self) {
    $self->openapi->valid_input or return;
    $self->render( openapi => $label->bibles );
}

sub payload ($self) {
    $self->openapi->valid_input or return;
    $self->render( openapi => decode_json(
        path(
            material_json(
                label => $self->param('label'),
                user  => $self->session('user_id'),
            )->{json_file}
        )->slurp
    ) );
}

sub _get_reference_data ($self) {
    return reference_data(
        user_id        => $self->session('user_id'),
        material_label => $self->param('label'),
        map { $_ => $self->param($_) } grep { defined $self->param($_) } qw(
            bible
            cover
            reference
            whole
            chapter
            phrases
            concordance
            force
            page_width
            page_height
            page_right_margin_left
            page_right_margin_right
            page_right_margin_top
            page_right_margin_bottom
            page_left_margin_left
            page_left_margin_right
            page_left_margin_top
            page_left_margin_bottom
        ),
    );
}

sub data ($self) {
    $self->openapi->valid_input or return;
    $self->render( openapi => _get_reference_data($self) );
}

sub html ($self) {
    $self->openapi->valid_input or return;
    $self->stash( skip_packer => 1 );
    $self->render( openapi => reference_html(
        $self,
        _get_reference_data($self),
    ) );
}

1;

=head1 NAME

QuizSage::Control::Api::Material

=head1 DESCRIPTION

This class is a subclass of L<Mojolicious::Controller> and provides handlers
for "Bible Materials" API calls.

=head1 METHODS

=head2 bibles

This endpoint returns a list of objects representing available Bible
translations.

=head2 payload

This endpoint wraps the C<material_json> function from
L<QuizSage::Util::Material>.

=head2 data

This endpoint wraps the C<reference_data> function from
L<QuizSage::Util::Reference>.

=head2 html

This endpoint wraps the C<reference_data> function from
L<QuizSage::Util::Reference> but renders the data returned from it into HTML,
then returns that HTML.

=head1 INHERITANCE

L<Mojolicious::Controller>.
