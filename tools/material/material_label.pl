#!/usr/bin/env perl
use exact -cli, -conf;
use QuizSage::Model::Label;
use Omniframe::Util::Table 'table';

my $opt = options( qw{
    user|u=s
    aliases|a
    name|n=s
    label|l=s
    public|p
    remove|r
    canonicalize|c
    descriptionize|d
} );

my $label = QuizSage::Model::Label->new( maybe user_id => $opt->{user} );

if ( $opt->{aliases} ) {
    my $aliases = $label->aliases;
    if (@$aliases) {
        say table(
            rows => $aliases,
            cols => [ qw( user_id name label public ) ],
        );
    }
    else {
        say 'No aliases';
    }
}
elsif ( $opt->{name} and $opt->{label} and not $opt->{remove} ) {
    if ( my $canonicalized_label = $label->canonicalize( $opt->{label} ) ) {
        $label->dq->sql(q{
            INSERT INTO label ( name, label, user_id, public ) VALUES ( ?, ?, ?, ? )
                ON CONFLICT( user_id, name ) DO UPDATE SET label = ?, user_id = ?, public = ?
        })->run(
            $opt->{name},
            (
                $canonicalized_label,
                $label->user_id,
                ( $opt->{public} ) ? 1 : 0,
            ) x 2,
        );
        say qq{"$opt->{name}" = "$canonicalized_label"};
    }
    else {
        say 'Label canonicalized into nothing';
    }
}
elsif ( ( $opt->{name} or $opt->{label} ) and $opt->{remove} ) {
    $label->delete({
        maybe user_id => $label->user_id,
        name          => $opt->{name} // $opt->{label},
    });
}
elsif (
    ( $opt->{name} or $opt->{label} ) and
    ( $opt->{canonicalize} or $opt->{descriptionize} )
) {
    say $label->canonicalize  ( $opt->{label} // $opt->{name} ) if ( $opt->{canonicalize}   );
    say $label->descriptionize( $opt->{label} // $opt->{name} ) if ( $opt->{descriptionize} );
}
else {
    pod2usage;
}

=head1 NAME

material_label.pl - Work with material labels including label storage

=head1 SYNOPSIS

    material_label.pl OPTIONS
        -u, --user   USER_ID_OR_EMAIL_ADDRESS
        -a, --aliases
        -n, --name   NAME
        -l, --label  CONTENT
        -p, --public
        -r, --remove
        -c, --canonicalize
        -d, --descriptionize
        -h, --help
        -m, --man

=head1 DESCRIPTION

This program will work with material labels including stored labeles in the
application database.

If a C<name> and C<label> are provided (and the C<remove> flag is not set), the
C<name> and C<label> are inserted or updated in the C<label> table of the
application database.

If the C<remove> flag is set and a C<name> or C<label> are provided, the
associated record in the C<label> table of the  application database is removed.

=head2 -u, --user

Optionally provide a user ID or a user email to identify a user for which other
commands should assume to be executed on behalf of. If not provided, other
commands assume no specific user.

=head2 -a, --aliases

List all aliases in scope. (Will consider the user if provided.)

=head2 -n, --name

Optionally provide the name of an alias, which may be stored in the C<label>
table of the application database.

=head2 -l, --label

Optionally provide the label value, which may be stored in the C<label> table
of the application database.

=head2 -p, --public

A flag that if set indicates that a database record that will be inserted or
updated should be marked public. Default is private.

=head2 -r, --remove

Remove a label identified by name or label in scope stored in in the C<label>
table of the application database. (Will consider the user if provided.)

=head2 -c, --canonicalize

Return a canonicalized label of the input label.

=head2 -d, --descriptionize

Return a descriptionized description of the input label.
