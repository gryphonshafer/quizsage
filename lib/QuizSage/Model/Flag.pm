package QuizSage::Model::Flag;

use exact -class, -conf;
use Mojo::JSON qw( to_json from_json );
use Mojo::Util qw( encode decode );
use Omniframe::Class::Time;
use Omniframe::Util::File 'opath';
use YAML::XS qw( Dump Load );

with 'Omniframe::Role::Model';

sub freeze ( $self, $data ) {
    $data->{data} = to_json( $data->{data} );
    undef $data->{data} if ( $data->{data} eq '{}' or $data->{data} eq 'null' );
    return $data;
}

sub thaw ( $self, $data ) {
    $data->{data} = ( defined $data->{data} ) ? from_json( $data->{data} ) : {};
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
        $input = Load( encode( 'UTF-8', $yaml ) );
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

    my $get_word_id = $dq->prepare_cached('SELECT word_id FROM word WHERE text = ?');
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
                $target = $get_word_id->run( $patch->{target} )->value;
                croak("Unable to locate target of $patch->{text}") unless ($target);
            }

            $patch_word->run(
                (
                    $target,
                    (
                        ( defined $patch->{meanings} )
                            ? to_json( $patch->{meanings} )
                            : $patch->{meanings}
                    ),
                    $patch->{text},
                ) x 2,
            );

            my $word_id = $get_word_id->run( $patch->{text} )->value;
            my @buffer;
            for my $synonym ( map { $_->{synonyms}->@* } $patch->{meanings}->@* ) {
                for my $word ( $synonym->{words}->@* ) {
                    push( @buffer, [ $word_id, $dq->quote($word), $synonym->{verity} ] );
                }
            }

            if (@buffer) {
                my %word_ids = map { $_->[0] => 1 } @buffer;
                $dq->do(
                    'DELETE FROM reverse WHERE word_id IN (' . join( ',', keys %word_ids ) . ')'
                );
                $dq->do(
                    'INSERT INTO reverse ( word_id, synonym, verity ) VALUES ' .
                    join( ',', map { '(' . join( ',', @$_ ) . ')' } @buffer )
                );
            }
        }
    }

    $dq->commit;

    # append to thesaurus patch log
    my $thesaurus_patch_log = opath( conf->get('thesaurus_patch_log'), { no_check => 1 } )->touch;
    my $thesaurus_patches   = Load( encode( 'UTF-8', $thesaurus_patch_log->slurp('UTF-8') ) ) // [];
    push( @$thesaurus_patches, {
        time       => $time->set->format('sqlite'),
        patch      => $input,
        maybe user => ($user)
            ? { map { $_ => $user->data->{$_} } qw( first_name last_name email phone ) }
            : undef,
    } );
    $thesaurus_patch_log->spew( decode( 'UTF-8', Dump($thesaurus_patches) ), 'UTF-8' );

    # remove all material JSON files
    opath( conf->get( qw{ material json location } ), { no_check => 1 } )->list->each('remove');

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
