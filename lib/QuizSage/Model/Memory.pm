package QuizSage::Model::Memory;

use exact -class;
use Bible::Reference;
use DateTime;
use Mojo::JSON 'encode_json';
use QuizSage::Model::Label;
use QuizSage::Model::User;
use QuizSage::Util::Material 'text2words';

with 'Omniframe::Role::Model';

class_has bible_ref => Bible::Reference->new;

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
        } $self->bible_ref->clear->acronyms(0)->sorting(1)->add_detail(1)->in(
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
        tiles  => $self->tiles( $user->id ),
        report => $self->report( $user->id ),

        shared_to => $self->dq->sql(q{
            SELECT
                u.user_id,
                u.first_name,
                u.last_name,
                u.email
            FROM shared_memory AS sm
            JOIN user AS u ON sm.shared_user_id = u.user_id
            WHERE sm.memorizer_user_id = ?
        })->run( $user->id )->all({}),

        shared_from => [
            map {
                +{
                    user   => $_,
                    tiles  => $self->tiles( $_->{user_id} ),
                    report => $self->report( $_->{user_id} ),
                };
            }
            $self->dq->sql(q{
                SELECT
                    u.user_id,
                    u.first_name,
                    u.last_name,
                    u.email
                FROM shared_memory AS sm
                JOIN user AS u ON sm.memorizer_user_id = u.user_id
                WHERE sm.shared_user_id = ?
            })->run( $user->id )->all({})->@*,
        ],
    };
}

sub tiles ( $self, $user_id ) {
    my %studying = map { @$_ } $self->dq->sql(q{
        SELECT
            STRFTIME( '%Y-%m-%d', created ),
            COUNT(*)
        FROM memory
        WHERE user_id = ? AND level > 0
        GROUP BY 1
        ORDER BY 1
    })->run($user_id)->all->@*;

    my $dt    = DateTime->now;
    my $today = $dt->ymd;

    $dt->subtract( years => 1 );
    $dt->subtract( days => $dt->dow ) if ( $dt->dow != 7 );

    my ( $weeks, $month, $date ) = ( [], '', '' );
    my @days;

    until ( $date eq $today ) {
        $date = $dt->ymd;

        push( @days, {
            strftime => $dt->strftime('%a %b %d'),
            verses   => $studying{$date} // 0,
        } );

        if ( $month ne $dt->month_abbr ) {
            delete $weeks->[0][0]{month} if ( @$weeks == 1 and $weeks->[0][0]{month} );
            $month = $days[0]{month} = $dt->month_abbr;
        }

        if ( @days == 7 ) {
            push( @$weeks, [@days] );
            @days = ();
        }

        $dt->add( days => 1 );
    }

    push( @$weeks, [@days] ) if (@days);
    return $weeks;
}

sub report ( $self, $user_id ) {
    $self->bible_ref->acronyms(1)->sorting(1)->add_detail(0);

    my $data;

    $data->{ $_->{level} }{ $_->{bible} } = $self->bible_ref->clear->in( $_->{label} )->refs for (
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

    my $all_blocks = [ map { +{
        bible => $_,
        refs  => $self->bible_ref->clear->in( join( '; ', $all->{$_}->@* ) )->refs,
    } } sort { $a cmp $b } keys %$all ];
    if (@$all_blocks) {
        my $user_data = QuizSage::Model::User->new->load($user_id)->data;
        unshift( @$data, {
            level  => 'all',
            blocks => $all_blocks,
            json   => encode_json({
                name   => $user_data->{first_name} . ' ' . $user_data->{last_name},
                blocks => $all_blocks,
            }),
        } );
    }

    return $data;
}

sub sharing ( $self, $data ) {
    $self->dq->sql(
        ( $data->{action} eq 'add' )
            ? q{
                INSERT OR IGNORE INTO shared_memory
                ( memorizer_user_id, shared_user_id ) VALUES ( ?, ? )
            }
            : q{
                DELETE FROM shared_memory
                WHERE memorizer_user_id = ? AND shared_user_id = ?
            }
    )->run( $data->{memorizer_user_id}, $data->{shared_user_id} );

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

=head2 review_verse

=head2 reviewed

=head2 state

=head2 tiles

=head2 report

=head2 sharing

=head1 WITH ROLE

L<Omniframe::Role::Model>.
