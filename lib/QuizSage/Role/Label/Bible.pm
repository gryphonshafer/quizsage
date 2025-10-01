package QuizSage::Role::Label::Bible;

use exact -role;
use Bible::Reference;

with 'Omniframe::Role::Database';

has 'bible_ref' => sub {
    Bible::Reference->new(
        acronyms   => 0,
        sorting    => 1,
        add_detail => 1,
    );
};

has 'bible_structure' => sub ($self) {
    return { map { $_->[0] => $_->[1] } $self->bible_ref->get_bible_structure->@* };
};

has 'bibles' => sub ($self) {
    return $self->dq('material')->sql(q{
        SELECT acronym, label, name, year
        FROM bible
        ORDER BY LENGTH(acronym) DESC, acronym
    })->run->all({});
};

has 'bible_acronyms' => sub ($self) {
    return $self->dq('material')->sql(q{
        SELECT acronym FROM bible ORDER BY LENGTH(acronym) DESC, acronym
    })->run->column;
};

sub canonicalize_refs ( $self, @refs ) {
    return $self->bible_ref->clear->simplify(1)->in(@refs)->refs;
}

sub versify_refs ( $self, @refs ) {
    return $self->bible_ref->clear->simplify(0)->in(@refs)->as_verses;
}

1;

=head1 NAME

QuizSage::Role::Label::Bible

=head1 SYNOPSIS

    package QuizSage::Model::Label;

    use exact -class;

    with 'QuizSage::Role::Label::Bible';

    sub attributes ($self) {
        return {
            bible_ref       => $self->bible_ref,
            bible_structure => $self->bible_structure,
            bibles          => $self->bibles,
            bible_acronyms  => $self->bible_acronyms,
        };
    }

    sub process_refs ( $self, @refs ) {
        return {
            canonical_refs => canonicalize_refs(@refs),
            verses         => versify_refs(@refs),
        };
    }

=head1 DESCRIPTION

This role provides Bible attributes and methods useful for label parsing and
formatting.

=head1 ATTRIBUTES

=head2 bible_ref

This is a L<Bible::Reference> object with suitable default properties set.

=head2 bible_structure

This is a processed data mapping of the Bible structure from
L<Bible::Reference>'s C<get_bible_structure>.

=head2 bibles

This is an arrayref of hashrefs of the supported Bibles in the application.

=head2 bible_acronyms

This is an arrayref of acronyms of Bibles supported in the application.

=head1 METHODS

=head2 canonicalize_refs

This method accepts any number of string inputs and returns a unified/simplified
Bible references string.

=head2 versify_refs

This method accepts any number of string inputs and returns an arrayref of
single-verse Bible references.

=head1 WITH ROLE

L<Omniframe::Role::Database>.

=head1 SEE ALSO

L<Bible::Reference>.
