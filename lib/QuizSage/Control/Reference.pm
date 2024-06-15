package QuizSage::Control::Reference;

use exact 'Mojolicious::Controller';

use Digest;

sub material ($self) {
    my $user           = $self->stash('user');
    my $quiz_defaults  = $user->conf->get('quiz_defaults');
    my $user_settings  = $user->data->{settings}{reference} // {};
    my $material_label = $user_settings->{material_label}   // $quiz_defaults->{material_label};
    my $material_id    = substr( Digest->new('SHA-256')->add($material_label)->hexdigest, 0, 16 );

    $self->warn(
        $material_label,
        $material_id,
    );

    $self->stash(
        material_label => $material_label,
        material_id    => $material_id,
    );
}

1;

=head1 NAME

QuizSage::Control::Reference

=head1 DESCRIPTION

This class is a subclass of L<Mojolicious::Controller> and provides handlers
for "Reference" actions.

=head1 METHODS

=head2 material

This controller handles material lookup display.

=head1 INHERITANCE

L<Mojolicious::Controller>.
