package QuizSage::Control::Label;

use exact 'Mojolicious::Controller';
use QuizSage::Model::Label;

sub tester ($self) {
    my $referrer = $self->param('referrer') // $self->req->headers->referrer;
    my $label    = QuizSage::Model::Label->new( user_id => $self->stash('user')->id );

    $self->stash(
        referrer      => $referrer,
        label_aliases => $label->aliases,
        bibles        => $label
            ->dq('material')
            ->get( 'bible', undef, undef, { order_by => 'acronym' } )
            ->run->all({}),
    );

    $self->stash(
        canonical_label       => $label->canonicalize( $self->param('label') ),
        canonical_description => $label->descriptionize( $self->param('label') ),
    ) if ( $self->param('label') );
}

sub editor ($self) {
    $self->redirect_to('/');
}

1;

=head1 NAME

QuizSage::Control::Label

=head1 DESCRIPTION

This class is a subclass of L<Mojolicious::Controller> and provides handlers
for "Label" actions.

=head1 METHODS

=head2 tester

This controller handles material label testing, where a user provides material
label/description input and gets back a canonical label and description.

=head2 editor

This controller handles editing material labels.

=head1 INHERITANCE

L<Mojolicious::Controller>.
