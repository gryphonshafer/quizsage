package QuizSage::Model::Memory;

use exact -class;
use Bible::Reference;
use DateTime;
use Mojo::JSON 'encode_json';
use QuizSage::Model::Label;
use QuizSage::Model::Season;
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
        $self->report( $user->id )->%*,
        tiles     => $self->tiles( $user->id ),
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
                    $self->report( $_->{user_id} )->%*,
                    user   => $_,
                    tiles  => $self->tiles( $_->{user_id} ),
                    json   => encode_json({
                        id   => $_->{user_id},
                        name => $_->{first_name} . ' ' . $_->{last_name},
                    }),
                };
            }
            $self->shared_from_users($user)->@*,
        ],
    };
}

sub shared_from_users ( $self, $user ) {
    return $self->dq->sql(q{
        SELECT
            u.user_id,
            u.first_name,
            u.last_name,
            u.email
        FROM shared_memory AS sm
        JOIN user AS u ON sm.memorizer_user_id = u.user_id
        WHERE sm.shared_user_id = ?
    })->run( $user->id )->all({});
}

sub tiles ( $self, $user_id ) {
    my %studying = map { @$_ } $self->dq->sql(q{
        SELECT
            STRFTIME( '%Y-%m-%d', created ),
            COUNT(*)
        FROM memory
        WHERE
            user_id = ? AND
            level > 0 AND
            created >= DATETIME( 'NOW', '-1 year' )
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
            date   => $date . ' 00:00:00',
            verses => $studying{$date} // 0,
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
    my $earliest_active_season_start;
    my $season  = QuizSage::Model::Season->new;
    my @seasons = sort { $a->{start} cmp $b->{start} } grep { $_->{active} } $season->seasons->@*;
    if (@seasons) {
        $earliest_active_season_start = $seasons[0]{start};
    }
    else {
        my $dt = DateTime->new(
            year      => DateTime->now->year + 1,
            month     => 8,
            day       => 1,
            time_zone => 'local',
        );
        $dt->set_year( $dt->year - 1 ) if ( $dt->epoch > time );
        $season->time->datetime($dt);
        $earliest_active_season_start = $season->time->format('sqlite_min');
    }

    my $data;
    push( @{ $data->{ $_->{level} } }, $_ ) for (
        _make_runs( $self->dq->sql(q{
            SELECT
                level,
                bible,
                book,
                chapter,
                GROUP_CONCAT( verse, ', ' ) AS verses,
                COUNT(*) AS number
            FROM memory
            WHERE
                user_id = ? AND
                level > 0 AND
                last_modified >= ?
            GROUP BY 1, 2, 3, 4
            ORDER BY 1 DESC, 2, 3, 4
        } )->run( $user_id, $earliest_active_season_start )->all({}) )->@*
    );

    return {
        report => [
            map {
                my $number;
                $number += $_->{number} for ( $data->{$_}->@* );
                +{
                    level  => $_,
                    number => $number,
                    data   => $data->{$_},
                };
            } sort { $b <=> $a } keys %$data
        ],
        earliest_active_season_start => $earliest_active_season_start,
    };
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

sub shared_labels ( $self, $user_id, $user_ids ) {
    return join( "\n",
        map {
            $_->{book} . ' ' . $_->{chapter} . ':' . $_->{run} . ' ' . $_->{bible}
        }
        _make_runs( $self->dq->sql(q{
            SELECT
                book,
                chapter,
                bible,
                GROUP_CONCAT( verse, ', ' ) AS verses
            FROM (
                SELECT
                    m.book,
                    m.chapter,
                    m.bible,
                    m.verse
                FROM shared_memory AS sm
                JOIN memory AS m ON sm.memorizer_user_id = m.user_id
                WHERE
                    m.level > 0 AND
                    m.last_modified >= DATETIME( 'NOW', '-1 year' ) AND
                    sm.shared_user_id = ? AND
                    sm.memorizer_user_id IN ( } . join( ', ', map { $self->dq->quote($_) } @$user_ids ) . q{ )
                GROUP BY 1, 2, 3, 4
            )
            GROUP BY 1, 2, 3
        } )->run($user_id)->all({}) )->@*
    );
}

sub _make_runs ($data) {
    return [ map {
        my @verses;
        for my $verse ( split( /\s*,\s*/, $_->{verses} ) ) {
            if ( @verses and not ref $verses[-1] and $verses[-1] + 1 == $verse ) {
                push( @verses, [ pop @verses, $verse ] );
            }
            elsif ( @verses and ref $verses[-1] and $verses[-1][1] + 1 == $verse ) {
                $verses[-1][1] = $verse;
            }
            else {
                push( @verses, $verse );
            }
        }
        $_->{runs} = \@verses;
        $_->{run}  = join( ', ', map { ( ref $_ ) ? join( '-', @$_ ) : $_ } @verses );
        $_;
    } @$data ];
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
hashrefs, each being a verse of data. Verse data includes C<book>, C<chapter>,
C<verse>, C<bible>, C<text>, a JSON-encoded string of the C<reference>, and the
memorization level of C<memorized>.

=head2 memorized

Saves the level of memorization of a verse. Requires a hashref containing the
keys C<user_id>, C<book>, C<chapter>, C<verse>, C<bible>, and C<level>.

=head2 review_verse

Requires a loaded L<QuizSage::Model::User> object. It will return either
C<undef> if there's no review data for the user, or if there is, a hashref of
data that includes the C<text> of the verse and the C<words> as an arrayref.

=head2 reviewed

This method requires a memory ID (primary key), a memorization level integer,
and a user ID (primary key). It will then save the level to that row in the
C<memory> database table.

=head2 state

Requires a loaded L<QuizSage::Model::User> object. Will return a hashref with
C<tiles> (from the C<tiles> method), C<report> (from the C<report> method),
C<shared_to> containing user information the state is shared to, and
C<shared_from> containing user, tiles, and report data of users shared to this
user.

=head2 shared_from_users

Requires a loaded L<QuizSage::Model::User> object. Will return an arrayref of
users shared to the provided user as hashrefs with basic user information.

=head2 tiles

Requires a user ID (primary key). Will return an arrayref of arrayrefs of days
data (including counts per day of verses memorized) suitable to create a tiles
display.

=head2 report

Requires a user ID (primary key). Will return a data structure suitable for
rendering a memorization report.

=head2 sharing

This method requires a hashref with keys C<memorizer_user_id> and
C<shared_user_id> along with C<action> which is expected to be either "add" or
"remove". The method will then either add or remove a shared memory state record
in the C<shared_memory> database table.

=head2 shared_labels

Requires a user ID (assumed to be a user making the request) and an arrayref of
user IDs (assumed to be user IDs shared with the user making the request). The
method will return a string where each line is a chapter reference label.

=head1 WITH ROLE

L<Omniframe::Role::Model>.
