package QuizSage::Model::Flag;

use exact -class, -conf;
use Mojo::JSON qw( encode_json decode_json );

with 'Omniframe::Role::Model';

sub freeze ( $self, $data ) {
    $data->{data} = encode_json( $data->{data} );
    undef $data->{data} if ( $data->{data} eq '{}' or $data->{data} eq 'null' );
    return $data;
}

sub thaw ( $self, $data ) {
    $data->{data} = ( defined $data->{data} ) ? decode_json( $data->{data} ) : {};
    return $data;
}

sub list ($self) {
    return $self->dq->sql(q{
        SELECT
            f.flag_id, f.source, f.url, f.report, f.data, f.created,
            u.first_name, u.last_name
        FROM flag AS f
        JOIN user AS u USING (user_id)
    })->run->all({});
}

1;

=head1 NAME

QuizSage::Model::Flag

=head1 SYNOPSIS

    use QuizSage::Model::Flag;

    my $flag_id = QuizSage::Model::Flag->new->create({
    });

=head1 DESCRIPTION

This class is the model for flag objects. A flag is like a notice of a possible
flaw in something in a query, material, or thesaurus.

=head1 METHODS

=head2 freeze

Likely not used directly, this method is provided such that
L<Omniframe::Role::Model> will JSON-encode the C<data> hashref.

=head2 thaw

Likely not used directly, C<thaw> will JSON-decode the C<data> hashref.

=head2 list

This method will return an arrayref of hashrefs of flag items suitable for
display in a flat items table.

=head1 WITH ROLE

L<Omniframe::Role::Model>.
