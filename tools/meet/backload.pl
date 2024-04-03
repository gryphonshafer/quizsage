#!/usr/bin/env perl
use exact -conf, -cli;
use Mojo::File 'path';
use Mojo::JSON 'decode_json';
use Omniframe::Class::Javascript;
use QuizSage::Model::Meet;
use QuizSage::Model::Quiz;
use QuizSage::Model::User;

my $opt = options( qw{
    season|s=s
    name|n=s
    input|i=s
    email|e=s
    bible|b=s@
    database|d
    ocjs|o
    print|p
    last|l
} );

pod2usage('Input text data file unreadable') unless ( -r $opt->{input} );
pod2usage('Not all required parameters provided')
    unless ( $opt->{season} and $opt->{name} and $opt->{email} and scalar @{ $opt->{bible} } );

my $meet_data = parse_meet_data( $opt->{input} );
my $root_dir  = conf->get( qw( config_app root_dir ) );
my $meet      = QuizSage::Model::Meet->new->from_season_meet( $opt->{season}, $opt->{name} );
my $user      = QuizSage::Model::User->new->load({ email => $opt->{email} });

pod2usage('Unable to find meet based on season and meet names provided') unless ($meet);
pod2usage('Unable to find user based on email provided') unless ($user);

my $js;
if ( $opt->{ocjs} ) {
    $js = Omniframe::Class::Javascript->with_roles('QuizSage::Role::JSApp')->new;
    $js = $js->new(
        basepath  => $root_dir . '/static/js/',
        importmap => $js->js_app_config('quiz')->{importmap},
    );
}

if ( $opt->{database} ) {
    $_->delete for (
        QuizSage::Model::Quiz->new->every({ meet_id => $meet->id })->@*
    );
}

for my $quiz_data (@$meet_data) {
    print "\n" if ( $opt->{print} and state $i++ );
    print_quiz_data($quiz_data) if ( $opt->{print} );

    my ($meet_data_quiz) =
        grep { $_->{name} eq $quiz_data->{quiz} }
        map { $_->{rooms}->@* }
        map { $_->{sets}->@* }
        grep { $_->{name} eq $quiz_data->{bracket} }
        $meet->data->{build}{brackets}->@*;

    my $quiz_settings = $meet->quiz_settings( $quiz_data->{bracket}, $quiz_data->{quiz} );

    $quiz_settings->{teams} = [
        map {
            my $team_name = $_;
            grep { $_->{name} eq $team_name } $meet->data->{build}{roster}->@*
        } $quiz_data->{teams}->@*
    ];

    my $id;
    $quiz_settings->{distribution} = [
        map {
            push( @{ $opt->{bible} }, shift @{ $opt->{bible} } );
            +{
                bible => $opt->{bible}[0],
                id    => ++$id,
                type  => $_,
            };
        } $quiz_data->{distribution}->@*
    ];

    $meet_data_quiz->{roster}       = $quiz_settings->{teams};
    $meet_data_quiz->{distribution} = $quiz_settings->{distribution};

    my $quiz_state = ( $opt->{ocjs} ) ? $js->run(
        q\
            import Quiz from 'classes/quiz';

            const quiz = new Quiz( OCJS.in );
            quiz.ready.then( () => {
                OCJS.in.events.forEach( event => {
                    let attempts = 0;
                    while ( attempts < 3 ) {
                        try {
                            quiz.queries.add_verse( quiz.board_row().query );
                            break;
                        }
                        catch (e) {
                            quiz.replace_query();
                        }
                    }
                    if ( attempts >= 3 ) throw 'Failed to add a verse';

                    quiz.action(
                        event.result,
                        ( ( event.team ) ? quiz.state.teams[ event.team - 1 ].id : null ),
                        (
                            ( event.quizzer )
                                ? quiz.state.teams[ event.team - 1 ].quizzers[ event.quizzer - 1 ].id
                                : null
                        ),
                        event.qss.join(''),
                    );
                } );

                OCJS.out( quiz.state );
                if ( quiz.board_row() ) throw 'Quiz incomplete';
            } );
        \,
        {
            material => {
                data => decode_json( path(
                    $root_dir . '/static/json/material/' . $quiz_settings->{material}{id} . '.json'
                )->slurp ),
            },
            quiz => {
                teams        => $quiz_settings->{teams},
                distribution => $quiz_settings->{distribution},
            },
            events => $quiz_data->{events},
        },
    )->[0][0] : undef;

    if ( $opt->{print} and $opt->{ocjs} ) {
        printf "%25d %12d %12d\n",
            map { $_->{score}{points} } $quiz_state->{teams}->@*;
    }

    QuizSage::Model::Quiz->new->create({
        meet_id     => $meet->id,
        user_id     => $user->id,
        bracket     => $quiz_data->{bracket},
        name        => $quiz_data->{quiz},
        settings    => $quiz_settings,
        maybe state => $quiz_state,
    }) if ( $opt->{database} );
}

$meet->save if ( $opt->{database} );

sub parse_meet_data ($meet_data_file) {
    my $data = path($meet_data_file)->slurp;
    $data =~ s/^#.*?$//mg;

    my @paragraphs = split( /\n\s+/, $data );
    @paragraphs = $paragraphs[-1] if ( $opt->{last} );

    return [
        map {
            my @parts = split(/\n/);

            my $quiz = {
                quiz         => uc shift @parts,
                distribution => [ map { uc } split( '', shift @parts ) ],
                teams => [ map { s/([a-z])(\d)/$1 $2/ir } split( '\|', uc shift @parts ) ],
            };

            $quiz->{bracket} =
                ( $quiz->{quiz} =~ /^\d/   ) ? 'Preliminary' :
                ( $quiz->{quiz} =~ /^a\d/i ) ? 'Auxiliary'   : 'Top 9';

            $quiz->{quiz} =~ s/\D+//g if ( $quiz->{bracket} eq 'Auxiliary' );

            $quiz->{events} = [ map {
                my $event = {
                    result => ( $_ eq '-' ) ? 'no_trigger' : ( s/\-// ) ? 'incorrect' : 'correct',
                };

                $event->{qss} = [];

                push( @{ $event->{qss} }, uc $1 ) while ( s/([a-z])//i );

                push( @{ $event->{qss} }, 'S' ) if (
                    $event->{result} ne 'no_trigger' and
                    not grep { $_ eq 'V' or $_ eq 'O' } $event->{qss}->@*
                );

                ( $event->{team}, $event->{quizzer} ) = ( $1, $2 ) if ( /(\d)(\d)/ );

                $event;
            } @parts ];

            $quiz;
        } @paragraphs
    ];
}

sub print_quiz_data ($quiz_data) {
    say '     Bracket: ' . $quiz_data->{bracket};
    say '        Quiz: ' . $quiz_data->{quiz};
    say 'Distribution: '
        . join( ' ', $quiz_data->{distribution}->@* )
        . ' (' . scalar( $quiz_data->{distribution}->@* ) . ')' . "\n";

    say '         QSS     1 2 3 4      1 2 3 4      1 2 3 4';
    my $i;
    for my $event ( $quiz_data->{events}->@* ) {
        my @row;
        if ( $event->{result} eq 'no_trigger' ) {
            @row = ('*') x 12;
        }
        else {
            @row = (' ') x 12;
            $row[
                ( ( $event->{team} // 0 ) - 1 ) * 4 + ( ( $event->{quizzer} // 0 ) - 1 )
            ] =
                ( $event->{result} eq 'correct'   ) ? '+' :
                ( $event->{result} eq 'incorrect' ) ? '-' :  '.';
        }

        printf "   %2d:   %-3s    |%s|%s|%s|%s|    |%s|%s|%s|%s|    |%s|%s|%s|%s|\n",
            ++$i,
            join( '', reverse sort $event->{qss}->@* ),
            @row;
    }
}

=head1 NAME

backload.pl - Backload meet quiz data

=head1 SYNOPSIS

    backload.pl OPTIONS
        -s, --season SEASON_NAME          # required
        -n, --name   MEET_NAME            # required
        -i, --input  INPUT_TEXT_DATA_FILE # required
        -e, --email  USER_EMAIL           # required
        -b, --bible  BIBLE_ACRONYM        # at least 1 required
        -d, --database
        -o, --ocjs
        -p, --print
        -l, --last
        -h, --help
        -m, --man

=head1 DESCRIPTION

This program will backload meet quiz data.

=head2 -s, --season

Season name. Required.

=head2 -n, --name

Meet name. Required.

=head2 -i, --input

Input text data file. Required.

This text file is expected to be a plain text file with "paragraphs" of data,
defined by at least 2 line breaks between each paragraph. A paragraph of data
represents a single quiz's data. For example:

    42
    pfqqpcqpfcfc
    team1|team2|team3
    32-
    -
    12-
    -
    21-
    o11
    o12
    -
    -
    o21
    -
    32
    -
    32
    11-
    32

The first line is the quiz's name. The second line is a sequence of base query
types for distribution rendering. The third line is a pipe-delimited list of
team names, but these names can be lowercase without spacing before any team
name number.

What follows thereafter are quiz events for correct, incorrect, and no trigger.
If the event is a no trigger, then the line will just contain "-". Otherwise,
the line will contain 2 numbers. The first is the team position number
(left-most starting at 1) and quizzer position number (left-most starting at 1)
of the event. Any quizzer-selected subtypes will be prepended. And if the result
was an incorrect ruling, then the line will be appended with "-".

=head2 -e, --email

User email address. Required.

=head2 -b, --bible

A Bible acronym. At least 1 is required.

=head2 -d, --database

Boolean. Write to database.

=head2 -o, --ocjs

Boolean. Use OCJS to build quiz state.

=head2 -p, --print

Boolean. Print quiz data.

=head2 -l, --last

Normally, this program will process all data in the input; however, if this flag
is set, it will only process the last "paragraph" (or quiz) of data. This allows
for a simple setup of a data-file-writing testing enviornment:

    while read -r newfile
    do
        ./tools/meet/backload.pl \
            -s "$SEASON_NAME" -n "$MEET_NAME" -e "$EMAIL" -b NIV \
            -i "$PATH_TO_DATA_FILE" -o -p -d -l
    done < <(inotifywait -m -e modify "$PATH_TO_DATA_FILE")
