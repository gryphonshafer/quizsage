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
    my $label = QuizSage::Model::Label->new( user_id => $self->stash('user')->id );

    if ( $self->param('id') and ( $self->param('action') // '' ) eq 'delete' ) {
        $label->load({
            label_id => $self->param('id'),
            user_id  => $self->stash('user')->id,
        })->delete;

        $self->redirect_to('/label/editor');
    }
    elsif ( $self->param('name') and $self->param('label') ) {
        my $parsed = $label->parse( $self->param('label') );
        delete $parsed->{bibles};

        my $data = {
            user_id => $self->stash('user')->id,
            public  => ( $self->param('public') ) ? 1 : 0,
            name    => $self->param('name'),
            label   => $label->format($parsed),
        };

        if ( not $data->{label} ) {
            $self->flash( memo => { class => 'error', message => 'Unable to parse the material label' } );
        }
        elsif ( not $self->param('id') ) {
            $label->create($data);
        }
        else {
            $label->load({
                label_id => $self->param('id'),
                user_id  => $self->stash('user')->id,
            })->save($data);
        }
        $self->redirect_to('/label/editor');
    }
    else {
        $self->stash(
            $label->load({
                label_id => $self->param('id'),
                user_id  => $self->stash('user')->id,
            })->data
        ) if ( $self->param('id') );

        $self->stash(
            label_aliases => [
                sort {
                    $a->{sort_name} cmp $b->{sort_name}
                }
                map {
                    $_->{sort_name} = lc $_->{name};
                    $_;
                }
                $label->every_data({ user_id => $self->stash('user')->id })->@*
            ],
        );
    }
}

my $bible_ref = QuizSage::Model::Label->new->bible_ref;

sub reference_parse ($self) {
    $self->openapi->valid_input or return;

    for (
        [ bible                 => 'Protestant' ],
        [ acronyms              => 0            ],
        [ sorting               => 1            ],
        [ require_chapter_match => 0            ],
        [ require_verse_match   => 0            ],
        [ require_book_ucfirst  => 0            ],
        [ minimum_book_length   => 3            ],
        [ add_detail            => 0            ],
    ) {
        my ( $attribute, $default ) = @_;
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

sub bible_books ($self) {
    $self->openapi->valid_input or return;
    $bible_ref->bible( $self->param('bible') // 'Protestant' );
    $self->render( openapi => scalar( $bible_ref->books ) );
}

sub bible_structure ($self) {
    $self->openapi->valid_input or return;
    $bible_ref->bible( $self->param('bible') // 'Protestant' );
    $self->render( openapi => scalar( $bible_ref->get_bible_structure ) );
}

sub identify_bible ($self) {
    $self->openapi->valid_input or return;
    $self->render( openapi => scalar( $bible_ref->identify_bible( $self->every_param('books')->@* ) ) );
}

1;

=head1 NAME

QuizSage::Control::Label

=head1 DESCRIPTION

This class is a subclass of L<Mojolicious::Controller> and provides handlers
for "Label" actions.

=head1 PAGE METHODS

=head2 tester

This controller handles material label testing, where a user provides material
label/description input and gets back a canonical label and description.

=head2 editor

This controller handles editing material labels.

=head1 API METHODS

=head2 reference_parse

This endpoint is intended to address Bible reference canonicalization. Given
some input, the endpoint will search for Bible references, canonicalize them,
and return them in various forms desired. It can return the canonicalized
within the context of the input string or strings as well.

The endpoint supports the Protestant Bible by default and by input setting
also the Orthodox Bible and the current Catholic Bible.

=head2 bible_books

Returns a list of books of the Bible, in order.

=head2 bible_structure

This endpoint will return an array containing an array per book (in order)
that contains two elements: the name of the book and an array of the maximum
verse number per chapter.

=head2 identify_bible

This endpoint is to help identify which Bible to use if you aren't sure. It
requires a list of strings as input, each string representing a book from the
Bible you're trying to identify. This method will then try to match these book
names across all Bibles and will return an array of the most likely Bibles for
your inputs.

=head1 INHERITANCE

L<Mojolicious::Controller>.
