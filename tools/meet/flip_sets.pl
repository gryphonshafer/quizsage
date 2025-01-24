#!/usr/bin/env perl
use exact -cli, -conf;
use QuizSage::Model::Meet;

my $opt = options( qw{ id|i=i bracket|b=s sets|s=s@ } );

pod2usage('Required input missing') unless ( $opt->{id} and $opt->{sets} and $opt->{sets}->@* );
$opt->{bracket} //= 'Preliminary';
$opt->{sets} = [ grep { $_ } map { split(/\D+/) } $opt->{sets}->@* ];
pod2usage('Sets provided need to be in even (pairs)') unless ( $opt->{sets}->@* and not $opt->{sets}->@* % 2 );

my $meet = deattry { QuizSage::Model::Meet->new->load( $opt->{id} ) };
die "Meet has not yet been built\n" unless ( $meet->data->{build} );

my ($bracket) = grep { $_->{name} eq $opt->{bracket} } $meet->data->{build}{brackets}->@*;
die "Bracket specified not found\n" unless ($bracket);

my $count = $meet->dq->sql('SELECT COUNT(*) FROM quiz WHERE meet_id = ? AND bracket = ? AND name = ?');
for my $name ( map { $_->{name} } map { $bracket->{sets}[ $_ - 1 ]{rooms}->@* } $opt->{sets}->@* ) {
    die "Quiz $name already exists and therefore prevents flipping its set\n"
        if ( $count->run( $opt->{id}, $opt->{bracket}, $name )->value );
}

while ( $opt->{sets}->@* ) {
    my ( $quizzes_a, $quizzes_b ) =
        map { $bracket->{sets}[ $_ - 1 ]->{rooms} }
        shift $opt->{sets}->@*, shift $opt->{sets}->@*;

    my @rosters_a = map { $_->{roster} } $quizzes_a->@*;
    my @rosters_b = map { $_->{roster} } $quizzes_b->@*;

    $_->{roster} = shift @rosters_b for ( $quizzes_a->@* );
    $_->{roster} = shift @rosters_a for ( $quizzes_b->@* );
}

$meet->save;

=head1 NAME

flip_sets.pl - Flip quiz sets in a built meet's schedule

=head1 SYNOPSIS

    flip_sets.pl OPTIONS
        -i, --id      MEET_PRIMARY_KEY_ID # required
        -b, --bracket BRACKET_NAME        # defaults to: "Preliminary"
        -s, --sets    SETS_TO_FLIP        # required; example: "3:4"
        -h, --help
        -m, --man

=head1 DESCRIPTION

This program will flip quiz sets in a built meet's schedule.

=head2 -i, --id

Meet primary key ID.

=head2 -b, --bracket

Bracket name. Defaults to "Preliminary".

=head2 -s, --sets

A string containing 2 digits representing the numbers of 2 sets that should be
flipped.
