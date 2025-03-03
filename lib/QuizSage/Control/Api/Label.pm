package QuizSage::Control::Api::Label;

use exact 'Mojolicious::Controller';
use QuizSage::Model::Label;

my $label = QuizSage::Model::Label->new;

sub aliases ($self) {
    $self->openapi->valid_input or return;
    $self->render( openapi => [
        map {
            +{
                name   => $_->{name},
                label  => $_->{label},
                author => {
                    first_name => $_->{first_name},
                    last_name  => $_->{last_name},
                    email      => $_->{email},
                },
                is_self_made  => $_->{is_self_made},
                public        => $_->{public},
                created       => $_->{created},
                last_modified => $_->{last_modified},
            }
        } $label->aliases( $self->session('user_id') )->@*
    ] );
}

sub parse ($self) {
    $self->openapi->valid_input or return;
    $self->render( openapi => $label->parse(
        $self->param('label'),
        $self->session('user_id'),
    ) );
}

1;

=head1 NAME

QuizSage::Control::Api::Label

=head1 DESCRIPTION

This class is a subclass of L<Mojolicious::Controller> and provides handlers
for "Material Labels" API calls.

=head1 METHODS

=head2 aliases

Returns an array of objects of aliases for the current authenticated user.

=head2 parse

Parses a label into a data structure.

=head1 INHERITANCE

L<Mojolicious::Controller>.
