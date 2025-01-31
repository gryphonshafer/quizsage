#!/usr/bin/env perl
use exact -cli, -conf;
use QuizSage::Model::Meet;

my $opt = options( qw{ id|i=i bracket|b=s sets|s=s@ quizzes|q=s@ } );

pod2usage('Required input missing') unless (
    $opt->{id} and (
        $opt->{sets} and $opt->{sets}->@* or
        $opt->{quizzes} and $opt->{quizzes}->@*
    )
);
$opt->{bracket} //= 'Preliminary';

$opt->{$_} = [ grep { $_ } map { split(/,/) } $opt->{$_}->@* ] for ( qw( sets quizzes ) );
pod2usage('Sets or quizzes provided need to be in even (pairs)') unless (
    $opt->{sets}->@* and not $opt->{sets}->@* % 2 or
    $opt->{quizzes}->@* and not $opt->{quizzes}->@* % 2
);

my $meet = deattry { QuizSage::Model::Meet->new->load( $opt->{id} ) };
die "Meet has not yet been built\n" unless ( $meet->data->{build} );

my ($bracket) = grep { $_->{name} eq $opt->{bracket} } $meet->data->{build}{brackets}->@*;
die "Bracket specified not found\n" unless ($bracket);

my $count = $meet->dq->sql('SELECT COUNT(*) FROM quiz WHERE meet_id = ? AND bracket = ? AND name = ?');
for my $name ( map { $_->{name} } map { $bracket->{sets}[ $_ - 1 ]{rooms}->@* } $opt->{sets}->@* ) {
    die "Quiz $name already exists and therefore prevents swapping its set\n"
        if ( $count->run( $opt->{id}, $opt->{bracket}, $name )->value );
}

while ( $opt->{sets}->@* ) {
    my @sets = ( shift $opt->{sets}->@*, shift $opt->{sets}->@* );
    my ( $quizzes_a, $quizzes_b ) = map { $bracket->{sets}[ $_ - 1 ]->{rooms} } @sets;

    if ( $quizzes_a->@* == $quizzes_b->@* ) {
        my @rosters_a = map { $_->{roster} } $quizzes_a->@*;
        my @rosters_b = map { $_->{roster} } $quizzes_b->@*;

        $_->{roster} = shift @rosters_b for ( $quizzes_a->@* );
        $_->{roster} = shift @rosters_a for ( $quizzes_b->@* );
    }
    else {
        my @names = map { $_->{name} } map { $_->{rooms}->@* } $bracket->{sets}->@*;

        my %set_a = $bracket->{sets}[ $sets[0] - 1 ]->%*;
        my %set_b = $bracket->{sets}[ $sets[1] - 1 ]->%*;

        my $schedule_a = $set_a{rooms}[0]{schedule};
        my $schedule_b = $set_b{rooms}[0]{schedule};

        $_->{schedule} = $schedule_b for ( $set_a{rooms}->@* );
        $_->{schedule} = $schedule_a for ( $set_b{rooms}->@* );

        %{ $bracket->{sets}[ $sets[0] - 1 ] } = %set_b;
        %{ $bracket->{sets}[ $sets[1] - 1 ] } = %set_a;

        $_->{name} = shift @names for ( map { $_->{rooms}->@* } $bracket->{sets}->@* );
    }
}

while ( $opt->{quizzes}->@* ) {
    my @quizzes = ( shift $opt->{quizzes}->@*, shift $opt->{quizzes}->@* );

    my ($quiz_a) = grep { $_->{name} eq $quizzes[0] } map { $_->{rooms}->@* } $bracket->{sets}->@*;
    my ($quiz_b) = grep { $_->{name} eq $quizzes[1] } map { $_->{rooms}->@* } $bracket->{sets}->@*;

    my $roster_a = $quiz_a->{roster};
    my $roster_b = $quiz_b->{roster};

    $quiz_a->{roster} = $roster_b;
    $quiz_b->{roster} = $roster_a;
}

$meet->save;

=head1 NAME

swap_quiz_rosters.pl - Swap quiz rosters in a built meet's schedule

=head1 SYNOPSIS

    swap_sets.pl OPTIONS
        -i, --id      MEET_PRIMARY_KEY_ID # required
        -b, --bracket BRACKET_NAME        # defaults to: "Preliminary"
        -s, --sets    SETS_TO_SWAP        # example: "3,4"
        -q, --quizzes QUIZZES_TO_SWAP     # example: "A,B"
        -h, --help
        -m, --man

=head1 DESCRIPTION

This program will swap quiz rosters in a built meet's schedule.

=head2 -i, --id

Meet primary key ID.

=head2 -b, --bracket

Bracket name. Defaults to "Preliminary".

=head2 -s, --sets

A string containing pairs of comma-separated digits representing the numbers of
sets that should be swapped.

=head2 -q, --quizzes

A string containing pairs of comma-separated names representing the names of
quizzes that should be swapped.
