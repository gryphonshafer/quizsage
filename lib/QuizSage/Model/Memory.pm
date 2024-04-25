package QuizSage::Model::Memory;

use exact -class;
use Bible::Reference;
use DateTime;
use Mojo::JSON 'encode_json';
use QuizSage::Model::Label;
use QuizSage::Util::Material 'text2words';

with 'Omniframe::Role::Model';

my $bible_ref = Bible::Reference->new;

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
        } $bible_ref->clear->acronyms(0)->sorting(1)->add_detail(1)->in(
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

sub review_verse( $self, $user ) {
    my $review_verse = $self->dq->sql(q{
        SELECT
            memory_id, book, chapter, verse, bible, level,
            JULIANDAY('NOW') - JULIANDAY(created) AS first_memorized,
            JULIANDAY('NOW') - JULIANDAY(last_modified) AS last_studied
        FROM memory
        WHERE user_id = ? AND level > 0
        ORDER BY level * 4 - last_studied, RANDOM()
    })->run( $user->id )->first({});

    return unless ($review_verse);

    $review_verse->{text} = $self->dq('material')->sql(q{
        SELECT v.text
        FROM verse AS v
        JOIN bible AS t USING (bible_id)
        JOIN book AS b USING (book_id)
        WHERE
            b.name    = ? AND
            v.chapter = ? AND
            v.verse   = ? AND
            t.acronym = ?
    })->run( @$review_verse{ qw( book chapter verse bible ) } )->value;

    $review_verse->{words} = text2words( $review_verse->{text}, 'skip_lc' );

    return $review_verse;
}

sub reviewed ( $self, $memory_id, $level, $user_id ) {
    $self->dq->sql(q{
        UPDATE memory SET level = ? WHERE memory_id = ? AND user_id = ?
    })->run( $level, $memory_id, $user_id );

    return;
}

sub state ( $self, $user ) {
    return {
        green_tiles => $self->green_tiles( $user->id ),
        report      => $self->report( $user->id ),
    };
}

sub green_tiles ( $self, $user_id ) {
    my %studying = map { @$_ } $self->dq->sql(q{
        SELECT
            STRFTIME( '%Y-%m-%d', last_modified ),
            COUNT(*)
        FROM memory
        WHERE user_id = ? AND level > 0
        GROUP BY 1
        ORDER BY 1
    })->run($user_id)->all->@*;

    my $dt    = DateTime->now;
    my $today = $dt->ymd;

    $dt->subtract( years => 1 );

    my $days = [];
    while ( not $days->[-1] or $days->[-1]{date} ne $today ) {
        my $date = $dt->ymd;
        my $dow  = $dt->dow;

        $dow = 0 if ( $dow == 7 );

        push( @$days, {
            date       => $date,
            verses     => $studying{$date} // 0,
            dow        => $dow,
            day_abbr   => $dt->day_abbr,
            month_abbr => $dt->month_abbr,
        } );

        $dt->add( days => 1 );
    }

    return $days;
}

sub report ( $self, $user_id ) {
    $bible_ref->acronyms(1)->sorting(1)->add_detail(0);

    my $data;

    $data->{ $_->{level} }{ $_->{bible} } = $bible_ref->clear->in( $_->{label} )->refs for (
        $self->dq->sql(q{
            SELECT level, bible, GROUP_CONCAT( books, '; ' ) AS label
            FROM (
                SELECT level, bible, book || ' ' || GROUP_CONCAT( chapters, '; ') AS books
                FROM (
                    SELECT level, bible, book, chapter || ':' || GROUP_CONCAT( verse, ', ' ) AS chapters
                    FROM memory
                    WHERE user_id = ? AND level > 0
                    GROUP BY 1, 2, 3, chapter
                )
                GROUP BY 1, 2, book
            )
            GROUP BY 1, 2
        })->run($user_id)->all({})->@*
    );

    my $all;

    $data = [ map {
        my $level = $_;
        +{
            level  => $level,
            blocks => [
                map {
                    push( @{ $all->{$_} }, $data->{$level}{$_} );
                    +{
                        bible => $_,
                        refs  => $data->{$level}{$_},
                    };
                }
                sort { $a cmp $b } keys %{ $data->{$level} }
            ],
        };
    } sort { $b <=> $a } keys %$data ];

    unshift( @$data, {
        level  => 'all',
        blocks => [ map { +{
            bible => $_,
            refs  => $bible_ref->clear->in( join( '; ', $all->{$_}->@* ) )->refs
        } } sort { $a cmp $b } keys %$all ],
    } );

    return $data;
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

=head2 review_verse

=head2 reviewed

=head2 state

=head2 green_tiles

=head2 report

=head1 WITH ROLE

L<Omniframe::Role::Model>.
