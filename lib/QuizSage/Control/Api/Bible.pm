package QuizSage::Control::Api::Bible;

use exact 'Mojolicious::Controller';
use QuizSage::Model::Label;

my $bible_ref = QuizSage::Model::Label->new->bible_ref;

sub parse_reference ($self) {
    $self->openapi->valid_input or return;

    for my $setting (
        [ bible                 => 'Protestant' ],
        [ acronyms              => 0            ],
        [ sorting               => 1            ],
        [ require_chapter_match => 0            ],
        [ require_verse_match   => 0            ],
        [ require_book_ucfirst  => 0            ],
        [ minimum_book_length   => 3            ],
        [ add_detail            => 0            ],
    ) {
        my ( $attribute, $default ) = @$setting;
        $bible_ref->$attribute( $self->param($attribute) // $default );
    }

    $bible_ref->clear;
    $bible_ref->in( $self->param('text') );

    $self->render( openapi => {
        map { $_ => scalar( $bible_ref->$_ ) } qw(
            refs as_books as_chapters as_runs as_verses as_hash as_array as_text
        )
    } );
}

sub books ($self) {
    $self->openapi->valid_input or return;
    $bible_ref->bible( $self->param('bible') // 'Protestant' );
    $self->render( openapi => scalar( $bible_ref->books ) );
}

sub structure ($self) {
    $self->openapi->valid_input or return;
    $bible_ref->bible( $self->param('bible') // 'Protestant' );
    $self->render( openapi => scalar( $bible_ref->get_bible_structure ) );
}

sub identify ($self) {
    $self->openapi->valid_input or return;
    $self->render( openapi => scalar( $bible_ref->identify_bible( $self->every_param('books')->@* ) ) );
}

1;

=head1 NAME

QuizSage::Control::Api::Bible

=head1 DESCRIPTION

This class is a subclass of L<Mojolicious::Controller> and provides handlers
for "Bible References" API calls.

=head1 METHODS

=head2 books

Returns a list of books of the Bible, in order.

=head2 identify

This endpoint is to help identify which Bible to use if you aren't sure. It
requires a list of strings as input, each string representing a book from the
Bible you're trying to identify. This method will then try to match these book
names across all Bibles and will return an array of the most likely Bibles for
your inputs.

=head2 parse_reference

This endpoint is intended to address Bible reference canonicalization. Given
some input, the endpoint will search for Bible references, canonicalize them,
and return them in various forms desired. It can return the canonicalized
within the context of the input string or strings as well.

The endpoint supports the Protestant Bible by default and by input setting
also the Orthodox Bible and the current Catholic Bible.

=head2 structure

This endpoint will return an array containing an array per book (in order)
that contains two elements: the name of the book and an array of the maximum
verse number per chapter.

=head1 INHERITANCE

L<Mojolicious::Controller>.
