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

sub canonicalize ($self) {
    $self->openapi->valid_input or return;

    my $canonicalize = $label->canonicalize(
        $self->param('label'),
        $self->session('user_id'),
    );

    $self->render(
        ($canonicalize)
            ? ( openapi => $canonicalize )
            : (
                status  => 400,
                openapi => {
                    errors => [ {
                        message => 'Failed to canonicalize label',
                        path    => $self->req->url->path->to_string,
                    } ],
                },
            ),
    );
}

sub descriptionize ($self) {
    $self->openapi->valid_input or return;

    my $descriptionize = $label->descriptionize(
        $self->param('label'),
        $self->session('user_id'),
    );

    $self->render(
        ($descriptionize)
            ? ( openapi => $descriptionize )
            : (
                status  => 400,
                openapi => {
                    errors => [ {
                        message => 'Failed to candescriptionize label',
                        path    => $self->req->url->path->to_string,
                    } ],
                },
            ),
    );
}

sub format ($self) {
    $self->openapi->valid_input or return;

    my $format = $label->format( $self->req->json );

    $self->render(
        ($format)
            ? ( openapi => $format )
            : (
                status  => 400,
                openapi => {
                    errors => [ {
                        message => 'Failed to format data structure',
                        path    => $self->req->url->path->to_string,
                    } ],
                },
            ),
    );
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

=head2 canonicalize

Canonicalize a label, maintaining valid and accessible aliases if any, and
unifying any intersections and/or filters.

=head2 descriptionize

Convert a label into a description, converting all valid and accessible aliases
to their associated label values, and processing any intersections and/or
filters.

=head2 format

Return a canonically formatted string given the input of a data structure you
might get from calling C<parse> on a string coming out of C<descriptionize>.

=head1 INHERITANCE

L<Mojolicious::Controller>.
