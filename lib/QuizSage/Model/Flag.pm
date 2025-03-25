package QuizSage::Model::Flag;

use exact -class, -conf;
use Mojo::JSON qw( encode_json decode_json );
use Omniframe::Class::Time;
use Omniframe::Util::File 'opath';
use YAML::XS qw( Dump Load );

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

my $time = Omniframe::Class::Time->new;

sub thesaurus_patch ( $self, $yaml, $user = undef ) {
    my $input;

    try {
        $input = Load($yaml);
    }
    catch ($e) {
        croak('Submitted YAML was not parse-able');
    }

    try {
        die if ( grep {
            not length( $_->{text} ) or
            length( $_->{text} ) and $_->{meanings} and $_->{target}
        } @$input );
    }
    catch ($e) {
        croak('All patches in the input must have a text value and not both meanings and target values.');
    }

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
            my $target;
            if ( defined $patch->{target} ) {
                $target = $redirect_id->run( $patch->{target} )->value;
                croak("Unable to locate target of $patch->{text}") unless ($target);
            }

            $patch_word->run(
                (
                    $target,
                    (
                        ( defined $patch->{meanings} )
                            ? encode_json( $patch->{meanings} )
                            : $patch->{meanings}
                    ),
                    $patch->{text},
                ) x 2,
            );
        }
    }

    my $thesaurus_patch_log = opath( conf->get('thesaurus_patch_log'), { no_check => 1 } )->touch;
    my $thesaurus_patches   = Load( $thesaurus_patch_log->slurp // [] );
    push( @$thesaurus_patches, {
        time       => $time->set->format('sqlite'),
        patch      => $input,
        maybe user => ($user)
            ? { map { $_ => $user->data->{$_} } qw( first_name last_name email phone ) }
            : undef,
    } );
    $thesaurus_patch_log->spew( Dump($thesaurus_patches) );

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
