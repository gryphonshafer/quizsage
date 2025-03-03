package QuizSage::Control::Api::Material;

use exact 'Mojolicious::Controller';
use QuizSage::Model::Label;

my $label = QuizSage::Model::Label->new;

sub bibles ($self) {
    $self->openapi->valid_input or return;
    $self->render( openapi => $label->bibles );
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

=head1 INHERITANCE

L<Mojolicious::Controller>.
