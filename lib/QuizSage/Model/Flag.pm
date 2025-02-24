package QuizSage::Model::Flag;

use exact -class;
use Mojo::JSON qw( encode_json decode_json );
use YAML::XS 'Load';

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
            u.first_name, u.last_name, u.email
        FROM flag AS f
        JOIN user AS u USING (user_id)
    })->run->all({});
}

sub thesaurus_patch ( $self, $yaml ) {
    my $input = Load($yaml);

    croak('All patches in the input must have a text value and not both meanings and target values.')
        if ( grep {
            not length( $_->{text} ) or
            length( $_->{text} ) and $_->{meanings} and $_->{target}
        } @$input );

    my $dq = $self->dq('material');

    my $redirect_id = $dq->prepare_cached('SELECT word_id FROM word WHERE text = ?');
    my $delete_word = $dq->prepare_cached('DELETE FROM word WHERE text = ?');
    my $patch_word  = $dq->prepare_cached(q{
        INSERT INTO word ( redirect_id, meanings, text )
        VALUES ( ?, ?, ? )
        ON CONFLICT (text) DO
        UPDATE SET redirect_id = ?, meanings = ? WHERE text = ?
    });

    $dq->begin_work;

    for my $patch (@$input) {
        if ( not $patch->{target} and not $patch->{meanings} ) {
            $delete_word->run( $patch->{text} );
        }
        else {
            $patch->{meanings} = encode_json( $patch->{meanings} ) if ( defined $patch->{meanings} );
            if ( defined $patch->{target} ) {
                $patch->{target} = $redirect_id->run( $patch->{target} )->value;
                croak("Unable to locate target of $patch->{text}") unless ( $patch->{target} );
            }

            $patch_word->run(
                (
                    $patch->{target},
                    $patch->{meanings},
                    $patch->{text},
                ) x 2,
            );
        }
    }

    $dq->commit;
    return;
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

=head2 thesaurus_patch

This method expects valid YAML that will be used to patch the application
thesaurus.

=head1 WITH ROLE

L<Omniframe::Role::Model>.
