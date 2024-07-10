package QuizSage::Control::Reference;

use exact 'Mojolicious::Controller';
use Digest;
use QuizSage::Util::Reference 'reference_data';

sub material ($self) {
    $self->warn('MATERIAL');

    # my $user           = $self->stash('user');
    # my $quiz_defaults  = $user->conf->get('quiz_defaults');
    # my $user_settings  = $user->data->{settings}{reference} // {};
    # my $material_label = $user_settings->{material_label}   // $quiz_defaults->{material_label};
    # my $material_id    = substr( Digest->new('SHA-256')->add($material_label)->hexdigest, 0, 16 );

    # $self->warn(
    #     $material_label,
    #     $material_id,
    # );

    # $self->stash(
    #     material_label => $material_label,
    #     material_id    => $material_id,
    # );
}

sub thesaurus ($self) {
    $self->warn('THESAURUS');
}

sub generator ($self) {
    my $ref_gen_params = $self->session('ref_gen_params') // {};

    $self->stash( %{
        reference_data(
            label     => $ref_gen_params->{material_label},
            bible     => $ref_gen_params->{bible},
            user_id   => $self->stash('user')->id,
            reference => ( ( $ref_gen_params->{reference} ) ? 1 : 0 ),
            map {
                $_ => ( $ref_gen_params->{$_} ) ? $ref_gen_params->{ $_ . '_number' } : 0
            } qw( whole chapter phrases )
        )
    } );
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

=head2 thesaurus

This controller handles thesaurus display.

=head2 generator

This controller handles material content document generation.

=head1 INHERITANCE

L<Mojolicious::Controller>.
