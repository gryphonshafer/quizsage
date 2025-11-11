#!/usr/bin/env perl
use exact -cli, -conf;
use Mojo::File 'path';
use Mojo::JSON 'from_json';
use Omniframe;
use Omniframe::Class::Javascript;
use QuizSage::Model::Label;
use QuizSage::Util::Material 'material_json';

my $opt = options( qw{
    label|l=s
    user|u=s
    force|f
    quizzes|q=i
    teams|t=i
} );

$opt->{quizzes} //= 100;
$opt->{teams}   //= 3;

my $label              = QuizSage::Model::Label->new( maybe user_id => $opt->{user} );
my $identified_aliases = $label->identify_aliases( $opt->{label} );
my $parsed_label       = $label->parse( $opt->{label} );

pod2usage('Unable to identify at least 1 alias in label')
    unless ( ref $identified_aliases eq 'ARRAY' and @$identified_aliases );

pod2usage('Unable to parse at least 1 primary translation from label') unless (
    ref $parsed_label eq 'HASH' and
    $parsed_label->{bibles} and
    $parsed_label->{bibles}{primary} and
    $parsed_label->{bibles}{primary}->@*
);

my $verse_aliases;
for my $alias (@$identified_aliases) {
    push( @{ $verse_aliases->{$_} }, $alias )
        for ( $label->versify_refs( $label->descriptionize($alias) )->@* );
}

my $result;
try {
    $result = material_json( map { $_ => $opt->{$_} } qw( label user force ) );
}
catch ($error) {
    pod2usage( deat $error );
}

my $quizzes = Omniframe::Class::Javascript->with_roles('QuizSage::Role::JSApp')
    ->new(
        basepath  => conf->get( qw( config_app root_dir ) ) . '/static/js/',
        importmap => Omniframe
            ->with_roles('QuizSage::Role::JSApp')->new
            ->js_app_config('queries')->{importmap},
    )->run(
        q`
            import distribution from 'modules/distribution';
            import Queries      from 'classes/queries';

            const queries = new Queries( { material: { data: OCJS.in.material_data } } );

            queries.ready.then( () => {
                [ ...Array( OCJS.in.quizzes_count ) ].forEach( () => {
                    OCJS.out(
                        ...distribution(
                            queries.constructor.types,
                            queries.material.primary_bibles,
                            OCJS.in.teams_count,
                        ).map( item => queries.create( item.type, item.bible ) )
                    );
                } );
            } );
        `,
        {
            material_data  => from_json( path( $result->{json_file} )->slurp('UTF-8') ),
            quizzes_count  => $opt->{quizzes},
            teams_count    => $opt->{teams},
        },
    );

my ( $alias_counts, $alias_counts_quizzes );
for my $quiz (@$quizzes) {
    my $alias_counts_per_quiz;

    for my $query (@$quiz) {
        my $aliases = join( ', ', @{
            $verse_aliases->{
                $query->{book} . ' ' . $query->{chapter} . ':' . $query->{verse}
            } // ['__NONE__']
        } );

        $alias_counts_per_quiz->{$aliases}++;
        $alias_counts->{$aliases}++;
    }

    push( @$alias_counts_quizzes, $alias_counts_per_quiz );
}
my ($max_length) = sort { $b <=> $a } map { length $_ } keys %$alias_counts;
my @widths = ( $max_length, 5, 7, 9, 9 );

printf '| ' . join( ' | ', map { '%-' . $_ . 's' } @widths ) . ' |' . "\n",
    'Alias', 'Mean', 'Std Dev', 'SD Min .5', 'SD Max .5';
print '|', join( '-:|', map { '-' x $_ } @widths ), '-:|', "\n";
for my $aliases ( sort keys %$alias_counts ) {
    my ( $std_dev, $mean ) = std_dev_mean( map { $_->{$aliases} // 0 } @$alias_counts_quizzes );
    printf "| %${max_length}s | %5.2f | %7.2f | %9.2f | %9.2f |\n",
        $aliases, $mean, $std_dev, $mean - $std_dev * 0.5, $mean + $std_dev * 0.5;
}

sub sum (@data) {
    my $sum = 0;
    $sum += $_ for @data;
    return $sum;
}

sub mean (@data) {
    return sum(@data) / @data;
}

sub std_dev_mean (@data) {
    return 0 if ( @data < 2 );

    my $mean             = mean(@data);
    my $squared_diff_sum = 0;

    for my $number (@data) {
        my $difference = $number - $mean;
        $squared_diff_sum += $difference ** 2;
    }

    return sqrt( $squared_diff_sum / ( @data - 1 ) ), $mean;
}

=head1 NAME

simulate.pl - Simulate quiz query building from an label containing aliases

=head1 SYNOPSIS

    simulate.pl OPTIONS
        -l, --label   LABEL_CONTENT
        -u, --user    USER_ID_OR_EMAIL_ADDRESS      # optional
        -f, --force                                 # defaults to false
        -q, --quizzes NUMBER_OF_QUIZZES             # defaults to 100
        -t, --teams   NUMBER_OF_TEAMS_IN_EACH_QUIZ  # defaults to 3
        -h, --help
        -m, --man

=head1 DESCRIPTION

This program will simulate quiz query building from a label It requires at
minimum a label containing at least 1 alias and 1 translation. You can
optionally provide a user ID to use when parsing and descriptionizing the label.

The program will generate queries for a given number of quizzes and return a
report of where the references originate.

=head2 -l, --label

A valid label containing at least 1 alias.

=head2 -u, --user

Optionally provide a user ID or a user email to identify a user for label
parsing and descriptionizing.

=head2 -f, --force

Will cause the material JSON data store to be rebuilt if it already exists.
Defaults to false.

=head2 -q, --quizzes

Number of quizzes to generate queries for. Defaults to 100.

=head2 -t, --teams

Number of teams in each simulated quiz. Defaults to 3.
