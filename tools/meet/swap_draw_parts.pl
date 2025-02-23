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
$meet->swap_draw_parts( $opt->{bracket}, $opt->{sets}, $opt->{quizzes} );

=head1 NAME

swap_draw_parts.pl - Swap draw parts (sets and/or quizzes) built meet's schedule

=head1 SYNOPSIS

    swap_sets.pl OPTIONS
        -i, --id      MEET_PRIMARY_KEY_ID # required
        -b, --bracket BRACKET_NAME        # defaults to: "Preliminary"
        -s, --sets    SETS_TO_SWAP        # example: "3,4"
        -q, --quizzes QUIZZES_TO_SWAP     # example: "A,B"
        -h, --help
        -m, --man

=head1 DESCRIPTION

This program will swap draw parts (sets and/or quizzes) built meet's schedule.

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
