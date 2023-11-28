#!/usr/bin/env perl
use exact -cli, -conf;
use QuizSage::Model::Meet;
use QuizSage::Model::Season;
use YAML::XS 'LoadFile';

my $opt = options( qw{
    context|c=s
    id|s=i
    season|e=s
    name|n=s
    location|l=s
    start|s=s
    days|d=i
    yaml|y=s
    action|a=s
} );

$opt->{context} =
    ( not $opt->{context}      ) ? ''       :
    ( $opt->{context} =~ /^s/i ) ? 'season' :
    ( $opt->{context} =~ /^m/i ) ? 'meet'   : '';

$opt->{action} =
    ( not $opt->{action}      ) ? ''       :
    ( $opt->{action} =~ /^b/i ) ? 'build'  :
    ( $opt->{action} =~ /^d/i ) ? 'delete' : '';

pod2usage('Most provide valid context and either a season name or meet name or primary ID') unless (
    $opt->{context} eq 'season' and $opt->{season} or
    $opt->{context} eq 'meet'   and $opt->{name}   or
    $opt->{context} and $opt->{id}
);

if ( $opt->{yaml} ) {
    die "Unable to read YAML file: $opt->{yaml}\n" unless ( -r $opt->{yaml} );
    $opt->{settings} = LoadFile( $opt->{yaml} ) or die "Unable to parse YAML file: $opt->{yaml}\n";
}

my $object = ( $opt->{context} eq 'season' ) ? QuizSage::Model::Season->new : QuizSage::Model::Meet->new;

my $season_id;
try {
    $season_id = QuizSage::Model::Season->new->load({ name => $opt->{season} })->id
        if ( $opt->{context} eq 'meet' and $opt->{season} );
}
catch ($e) {
    die $object->deat($e) . "\n";
}

my $data = {
    maybe season_id => $season_id,
    maybe name      => $opt->{ ( $opt->{context} eq 'season' ) ? 'season' : 'name' },
    maybe location  => $opt->{location},
    maybe start     => $opt->{start},
    maybe days      => $opt->{days},
    maybe settings  => $opt->{settings},
};

try {
    $object->load(
        ( $opt->{id} )
            ? $opt->{id}
            : { name => $opt->{ ( $opt->{context} eq 'season' ) ? 'season' : 'name' } }
    )->save($data);
}
catch ($e) {
    $object->create($data) unless ( $opt->{action} eq 'delete' );
}

if ( $opt->{action} and ( not $object or not $object->data ) ) {
    die "Unable to $opt->{action} without loadable $opt->{context}\n";
}
elsif ( $opt->{action} eq 'delete' ) {
    $object->delete;
}
elsif ( $opt->{action} and not $object->can( $opt->{action} ) ) {
    die "Class $opt->{context} cannot $opt->{action}\n";
}
elsif ( $opt->{action} ) {
    my $method = $opt->{action};
    $object->$method;
}

=head1 NAME

meet.pl - Build and edit meets and seasons

=head1 SYNOPSIS

    meet.pl OPTIONS
        -c, --context  CONTEXT # season | meet
        -e, --season   SEASON_NAME
        -n, --name     MEET_NAME
        -l, --location LOCATION
        -s, --start    DATETIME|EPOCH
        -d, --days     DURATION
        -y, --yaml     YAML_SETTINGS_FILE
        -a, --action   ACTION # build | delete
        -h, --help
        -m, --man

=head1 DESCRIPTION

This program will build and edit meets and seasons.

=head2 -c, --context

Run the program either in the "season" or "meet" context.

=head2 -e, --season

Season name.

=head2 -n, --name

Meet name.

=head2 -l, --location

Location name.

=head2 -s, --start

Season or meet start date and time, either as some sort of parsable date/time
string (with or without timezone) or epoch.

=head2 -d, --days

Number of days of season or meet duration.

=head2 -y, --yaml

YAML source file for settings.

=head2 -a, --action

Execute a valid action. Valid actions are: "build" and "delete".
