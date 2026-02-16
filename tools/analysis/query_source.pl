#!/usr/bin/env perl
use exact -conf, -cli;
use QuizSage::Model::Label;
use QuizSage::Model::Meet;
use QuizSage::Model::Quiz;
use Text::CSV_XS;

my $opt = options( qw{ meet_id|m=i type|t=s } );
$opt->{type} //= 'full';

my $meet;
try {
    $meet = QuizSage::Model::Meet->new->load( $opt->{meet_id} );
}
catch ($e) {
    pod2usage('Must provide a valid meet ID');
}

sub get_aliases ($input) {
    my @aliases;
    if ( ref $input eq 'ARRAY' ) {
        @aliases = map { get_aliases($_) } @$input;
    }
    elsif ( ref $input eq 'HASH' ) {
        @aliases = (
            @{ $input->{aliases} // [] },
            map { get_aliases( $input->{$_} ) } keys %$input
        );
    }
    return @aliases;
}

{
    my $label = QuizSage::Model::Label->new;
    my $versified_aliases_cache;
    sub versified_aliases ($label_text) {
        return $versified_aliases_cache->{$label_text} if ( $versified_aliases_cache->{$label_text} );
        my $aliases = { map { $_->{name} => $_->{label} } get_aliases( $label->parse($label_text) ) };
        $aliases->{$_} = $label->versify_refs( $label->descriptionize( $aliases->{$_} ) )
            for ( keys %$aliases );
        $versified_aliases_cache->{$label_text} = $aliases;
        return $aliases;
    }
}

my ( $data, $uniques );
for my $quiz (
    sort {
        ( $a->data->{name} =~ /^\d+$/ and $b->data->{name} =~ /^\d+$/ )
            ? $a->data->{name} <=> $b->data->{name}
            : $a->data->{name} cmp $b->data->{name}
    }
    QuizSage::Model::Quiz->new->every( { meet_id => $meet->id } )->@*
) {
    my $versified_aliases = versified_aliases( $quiz->data->{settings}{material}{label} );
    push( @{ $data->{ $quiz->data->{bracket} } }, $_ ) for (
        map {
            my $row     = $_;
            my $query   = $row->{query}{original} // $row->{query};
            my $ref     = $query->{book} . ' ' . $query->{chapter} . ':' . $query->{verse};
            my $aliases = [
                sort
                grep {
                    grep { $_ eq $ref } $versified_aliases->{$_}->@*
                } keys %$versified_aliases
            ];
            my $aliases_string = join( ', ', @$aliases ) || '(None)';

            $row->{id} =~ /^(?<number>\d+)(?<letter>\w+)$/;

            $uniques->{aliases}{$aliases_string} = 1;
            $uniques->{letters}{ $+{letter}    } = 1;

            +{
                %+,
                ref            => $ref,
                aliases        => $aliases,
                aliases_string => $aliases_string,
                quiz           => $quiz->data->{name},
            };
        }
        grep { $_->{query} }
        $quiz->data->{state}{board}->@*
    );
}

my $csv = Text::CSV_XS->new;

if ( lc( substr( $opt->{type}, 0, 1 ) ) eq 'f' ) {
    for my $bracket_name ( map { $_->{name} } $meet->data->{build}{brackets}->@* ) {
        for my $query_row ( $data->{$bracket_name}->@* ) {
            $csv->combine(
                $bracket_name,
                @$query_row{ qw( quiz number letter ref ) },
                @{ $query_row->{aliases} // [] },
            );
            say $csv->string;
        }
    }
}
elsif ( lc( substr( $opt->{type}, 0, 1 ) ) eq 'b' ) {
    for my $bracket_name ( map { $_->{name} } $meet->data->{build}{brackets}->@* ) {
        for my $aliases ( sort keys $uniques->{aliases}->%* ) {
            $csv->combine(
                $bracket_name,
                $aliases,
                scalar( grep { $_->{aliases_string} eq $aliases } $data->{$bracket_name}->@* ),
            );
            say $csv->string;
        }
    }
}
elsif ( lc( substr( $opt->{type}, 0, 1 ) ) eq 'l' ) {
    for my $bracket_name ( map { $_->{name} } $meet->data->{build}{brackets}->@* ) {
        for my $aliases ( sort keys $uniques->{aliases}->%* ) {
            for my $letter ( sort keys $uniques->{letters}->%* ) {
                $csv->combine(
                    $bracket_name,
                    $aliases,
                    $letter,
                    scalar( grep {
                        $_->{letter} eq $letter and
                        $_->{aliases_string} eq $aliases
                    } $data->{$bracket_name}->@* ),
                );
                say $csv->string;
            }
        }
    }
}

=head1 NAME

query_source.pl - Report query source counts for a meet

=head1 SYNOPSIS

    query_source.pl OPTIONS
        -m, --meet_id INTEGER
        -t, --type    REPORT_TYPE  # "full" (default), "brackets", "letters"
        -h, --help
        -m, --man

=head1 DESCRIPTION

This program will report query source counts for a meet as CSV.

    ./query_source.pl -m 42 -t letters > 42_letters.csv

=head2 -m, --meet_id

The database primary key for the meet to report on.

=head2 -t, --type

Select the type of report. Options are "full" (default), "brackets", and
"letters".
