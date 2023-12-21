package QuizSage::Model::Quiz;

use exact -class;
use Mojo::JSON qw( encode_json decode_json );

with 'Omniframe::Role::Model';

sub freeze ( $self, $data ) {
    for ( qw( application settings state ) ) {
        $data->{$_} = encode_json( $data->{$_} ) if ( defined $data->{$_} );
    }

    return $data;
}

sub thaw ( $self, $data ) {
    for ( qw( application settings state ) ) {
        $data->{$_} = decode_json( $data->{$_} ) if ( defined $data->{$_} );
    }

    return $data;
}

1;

=head1 NAME

QuizSage::Model::Quiz

=head1 SYNOPSIS

    use QuizSage::Model::Quiz;

    my $quiz = QuizSage::Model::Quiz->new;

=head1 DESCRIPTION

This class is the model for quiz objects.

=head1 OBJECT METHODS

=head2 freeze, thaw

=head1 WITH ROLE

L<Omniframe::Role::Model>.
