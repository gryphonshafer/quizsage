package QuizSage::Model::Memory;

use exact -class;
use Bible::Reference;
use Mojo::JSON 'encode_json';
use QuizSage::Model::Label;

with 'Omniframe::Role::Model';

my $bible_ref = Bible::Reference->new(
    acronyms   => 0,
    sorting    => 1,
    add_detail => 1,
);

sub to_memorize ( $self, $user ) {
    my $quiz_defaults = $self->conf->get('quiz_defaults');
    my $user_settings = $user->data->{settings}{memorize}  // {};
    my $label         = QuizSage::Model::Label->new( user_id => $user->id );
    my $material_data = $label->parse( $user_settings->{material_label} // $quiz_defaults->{material_label} );

    my %bibles = map { map { $_ => 1 } $material_data->{bibles}{$_}->@* } keys $material_data->{bibles}->%*;
    my @bibles = keys %bibles;

    my $sth_text = $self->dq('material')->sql(q{
        SELECT v.text
        FROM verse AS v
        JOIN bible AS t USING (bible_id)
        JOIN book AS b USING (book_id)
        WHERE
            b.name    = ? AND
            v.chapter = ? AND
            v.verse   = ? AND
            t.acronym = ?
    });

    my $sth_level = $self->dq->sql(q{
        SELECT level
        FROM memory
        WHERE
            user_id = ? AND
            book    = ? AND
            chapter = ? AND
            verse   = ? AND
            bible   = ?
    });

    return [
        map {
            my ( $book, $chapter, $verse ) = m/^(.+)\s+(\d+):(\d+)$/;
            map {
                my $reference = {
                    book    => $book,
                    chapter => $chapter,
                    verse   => $verse,
                    bible   => $_,
                };

                +{
                    %$reference,
                    text      => $sth_text->run( $book, $chapter, $verse, $_ )->value,
                    reference => encode_json($reference),
                    memorized => $sth_level->run( $user->id, $book, $chapter, $verse, $_ )->value // 0,
                };
            } @bibles;
        } $bible_ref->clear->in(
            join( '; ', map { $_->{range}->@* } $material_data->{ranges}->@* )
        )->as_verses->@*
    ];
}

sub memorized ( $self, $data ) {
    $self->dq->sql(q{
        INSERT OR REPLACE INTO memory ( user_id, book, chapter, verse, bible, level )
        VALUES ( ?, ?, ?, ?, ?, ? )
    })->run( @$data{ qw( user_id book chapter verse bible level ) } );

    return;
}

1;

=head1 NAME

QuizSage::Model::Memory

=head1 SYNOPSIS

    use QuizSage::Model::Memory;

=head1 DESCRIPTION

This class is the model for memory objects.

=head1 OBJECT METHODS

=head2 to_memorize

Requires a loaded L<QuizSage::Model::User> object. Returns an arrayref of
hashrefs, each being a verse of data.

=head2 memorized

Saves the level of memorization of a verse.

=head1 WITH ROLE

L<Omniframe::Role::Model>.
