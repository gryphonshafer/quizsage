package QuizSage::Model::Quiz;

use exact -class;
use Mojo::JSON qw( encode_json decode_json );

with qw( Omniframe::Role::Model Omniframe::Role::Time );

sub freeze ( $self, $data ) {
    for ( qw( importmap settings state ) ) {
        $data->{$_} = encode_json( $data->{$_} ) if ( defined $data->{$_} );
    }

    return $data;
}

sub thaw ( $self, $data ) {
    for ( qw( importmap settings state ) ) {
        $data->{$_} = decode_json( $data->{$_} ) if ( defined $data->{$_} );
    }

    # if ( $data->{settings}{teams} ) {
    #     $data->{settings}{teams} = [ map {
    #         +{
    #             name     => $_,
    #             quizzers => $self->dq->sql(q{
    #                 SELECT
    #                     q.quizzer_id AS id,
    #                     q.name,
    #                     r.bible
    #                 FROM registration r
    #                 JOIN quizzer q USING (quizzer_id)
    #                 WHERE r.meet_id = ? AND r.team = ?
    #             })->run( $data->{meet_id}, $_ )->all({}),
    #         }
    #     } $data->{settings}{teams}->@* ];
    # }

    return $data;
}

sub active_quizzes ($self) {
    my $rooms;
    my $seasons = [ map {
        $_->{meets} = [ map {
            $_->{quizzes} = [ map {
                $_->{scheduled_start} =
                    $self->time->parse( $_->{scheduled_start} )->strftime('%a %b %e %l:%M %p');
                $rooms->{ $_->{room} } = 1;

                $_->{settings} = ( defined $_->{settings} ) ? decode_json( $_->{settings} ) : {};
                $_->{state}    = ( defined $_->{state}    ) ? decode_json( $_->{state}    ) : {};

                $_->{settings_state} = { $_->{settings}->%*, $_->{state}->%* };

                $_;
            } $self->dq->sql(q{
                SELECT
                    quiz_id,
                    name,
                    password,
                    room,
                    scheduled_start,
                    scheduled_duration,
                    settings
                FROM quiz
                WHERE meet_id = ?
                ORDER BY scheduled_start, room
            })->run( $_->{meet_id} )->all({})->@* ];
            $_;
        } $self->dq->sql('SELECT * FROM meet WHERE season_id = ?')->run( $_->{season_id} )->all({})->@* ];
        $_;
    } $self->dq->sql('SELECT * FROM season')->run->all({})->@* ];

    $rooms = [ sort { ( $a =~ /^[\d\.]$/ and $b =~ /^[\d\.]$/ ) ? $a <=> $b : $a cmp $b } keys %$rooms ];

    return {
        seasons => $seasons,
        rooms   => $rooms,
    };
};

1;

=head1 NAME

QuizSage::Model::Quiz

=head1 SYNOPSIS

    use QuizSage::Model::Quiz;

    my $quiz = QuizSage::Model::Quiz->new;

=head1 DESCRIPTION

This class is the model for quiz objects.

=head1 OBJECT METHODS

=head2 active_quizzes

=head1 WITH ROLE

L<Omniframe::Role::Model>.
