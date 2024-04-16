#!/usr/bin/env perl
use exact -cli, -conf;
use Bible::Reference;
use Mojo::JSON 'decode_json';
use Omniframe;
use QuizSage::Model::Meet;
use YAML::XS qw( LoadFile Load Dump );

my $opt = options( qw{
    yaml|y=s
    example|x
} );

pod2usage('Must provide either YAML input or ask for YAML example')
    unless ( $opt->{yaml} or $opt->{example} );

pod2usage('Unable to read from file: ' . $opt->{yaml} ) if ( $opt->{yaml} and not -r $opt->{yaml} );

if ( $opt->{example} ) {
    say Dump( {
        'Galatians, Ephesians, Philippians, Colossians' => {
            'District Meet 3' => {
                'Old' => 'Ephesians; Galatians 1-4',
                'New' => 'Galatians 5-6; Philippians 1-2',
            },
            'District Meet 5' => {
                'Old' => 'Ephesians; Galatians; Philippians; Colossians 1',
                'New' => 'Colossians 2-4',
            },
        },
    } );

    exit;
}

my $meet_info = LoadFile( $opt->{yaml} );

my $dq = Omniframe->with_roles('+Database')->new->dq;

my $sth_season_id = $dq->sql('SELECT season_id FROM season WHERE name = ?');
my $sth_meet_id   = $dq->sql('SELECT meet_id FROM meet WHERE season_id = ? AND name = ?');

my $bible_ref = Bible::Reference->new(
    acronyms   => 0,
    sorting    => 1,
    add_detail => 1,
);

my $label_sizes;
my $verses_labels;

for my $label (
    $dq->sql('SELECT name, label FROM label WHERE user_id IS NULL AND public')->run->all({})->@*
) {
    my $verses = $bible_ref->clear->in( $label->{label} )->as_verses;
    $label_sizes->{ $label->{name} } = @$verses;
    push( @{ $verses_labels->{$_} }, $label->{name} ) for (@$verses);
}

( $verses_labels->{$_} ) =
    map { $_->[0] }
    sort { $a->[1] <=> $b->[1] }
    map { [ $_, $label_sizes->{$_} ] }
    $verses_labels->{$_}->@*
    for ( keys %$verses_labels );

$meet_info = {
    map {
        my $season_name = $_;
        my $season_id   = $sth_season_id->run($season_name)->value;
        map {
            my $meet_name = $_;

            $sth_meet_id->run( $season_id, $meet_name )->value => {
                map {
                    my $type = $_;
                    map {
                        $_ => {
                            type => $type,
                        }
                    } $bible_ref->clear->in( $meet_info->{$season_name}{$meet_name}{$type} )->as_verses->@*
                } keys %{ $meet_info->{$season_name}{$meet_name} }
            };
        } keys %{ $meet_info->{$season_name} };
    } keys %$meet_info
};

my @meet_ids = sort keys %$meet_info;

my $stats = { map {
    $_ => {
        map {
            $_->{name} => $_->{points_avg},
        } QuizSage::Model::Meet->new->load($_)->stats->{quizzers}->@*
    }
} @meet_ids };

my $meet_names = { map {
    $_ => $dq->sql('SELECT name FROM meet WHERE meet_id = ?')->run($_)->value
} @meet_ids };

my $ph  = join( ', ', map { '?' } @meet_ids );
my $set = $dq->sql(qq{
    SELECT meet_id, bracket, name, state
    FROM quiz
    WHERE meet_id IN ($ph)
})->run(@meet_ids);

say join( ',',
    'Meet',
    'Bracket',
    'Quiz',
    'QryNum',
    'QryLtr',
    'Reference',
    'Label',
    'Type',
    'Result',
    'Base',
    'QSS',
    'Team',
    'Quizzer',
    'Average',
);

while ( my $quiz = $set->next ) {
    my $data       = $quiz->data;
    $data->{state} = decode_json $data->{state};

    my $quizzer_names = {
        map { $_->{id} => $_->{name} } map { $_->{quizzers}->@* } $data->{state}{teams}->@*
    };

    my $team_names = {
        map { $_->{id} => $_->{name} } $data->{state}{teams}->@*
    };

    for my $board ( $data->{state}{board}->@* ) {
        next if (
            $board->{action} ne 'no_trigger' and
            $board->{action} ne 'correct' and
            $board->{action} ne 'incorrect'
        );

        my ($verse)    = split( /\+/, $board->{query}{verse} );
        my $reference  = $board->{query}{book} . ' ' . $board->{query}{chapter} . ':' . $verse;
        my $verse_info = $meet_info->{ $data->{meet_id} }{$reference};

        say join( ',',
            $meet_names->{ $data->{meet_id} },
            $data->{bracket},
            $data->{name},
            substr( $board->{id}, 0, length( $board->{id} ) - 1 ),
            ( ord( substr( $board->{id}, length( $board->{id} ) - 1, 1 ) ) - 64 ),
            $reference,
            $verses_labels->{$reference} // 'Full Material',
            $verse_info->{type},
            join( ' ', map { ucfirst } split( /_/, $board->{action} ) ),
            $board->{query}{type},
            $board->{qsstypes} // '',
            $team_names->{ $board->{team_id} // '' } // '',
            $quizzer_names->{ $board->{quizzer_id} // '' } // '',
            $stats->{ $data->{meet_id} }{ $quizzer_names->{ $board->{quizzer_id} // '' } // '' } // '',
        );
    }
}

=head1 NAME

performance.pl - Dump CSV file of meet performance data

=head1 SYNOPSIS

    performance.pl OPTIONS
        -y, --yaml     YAML_SETTINGS_FILE
        -x, --example
        -h, --help
        -m, --man

=head1 DESCRIPTION

This program will dump CSV file of meet performance data.

=head2 -y, --yaml

YAML source file for settings.

=head2 -x, --example

Output example input YAML.
