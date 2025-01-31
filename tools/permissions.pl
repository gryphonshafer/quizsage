#!/usr/bin/env perl
use exact -cli, -conf;
use Mojo::File 'path';
use Cwd 'getcwd';

my $opt = options( qw{
    cli_user|u=s
    cli_group|g=s
    ops_user|r=s
    ops_group|p=s
} );

pod2usage('Must supply values for at least: cli_user and ops_user')
    if ( grep { not $opt->{$_} } qw( cli_user ops_user ) );

$opt->{ $_ . '_group' } //= $opt->{ $_ . '_user' } for ( qw( cli ops ) );

my ( $original_cwd, $root_dir ) = ( getcwd(), conf->get( qw( config_app root_dir ) ) );
chdir $root_dir if ( $original_cwd ne $root_dir );

my $permissions = {
    '__default'                => { usr => $opt->{cli_user}, grp => $opt->{cli_group} },
    '__directory'              => { prm => '0775' },
    '__file'                   => { prm => '0664' },
    'config/db/dest.wrap'      => { prm => '0775' },
    'local'                    => { grp => $opt->{ops_group} },
    'local/config.yaml'        => { prm => '0640', grp => $opt->{ops_group} },
    'local/access.log'         => { prm => '0660', usr => $opt->{ops_user}, grp => $opt->{ops_group} },
    'local/app.log'            => { prm => '0660', usr => $opt->{ops_user}, grp => $opt->{ops_group} },
    'local/db'                 => { grp => $opt->{ops_group} },
    'local/db/app.sqlite'      => { prm => '0660', grp => $opt->{ops_group} },
    'local/db/material.sqlite' => { prm => '0640', grp => $opt->{ops_group} },
    'static'                   => { grp => $opt->{ops_group} },
    'static/build'             => { grp => $opt->{ops_group} },
    'static/build/app.css'     => { usr => $opt->{ops_user}, grp => $opt->{ops_group} },
    'local/ttc'                => { ignore => 1 },
    'local/ttc/*'              => { ignore => 1 },
    '*.pl'                     => { prm => '0775' },
    '*.psgi'                   => { prm => '0775' },
};

path->list_tree({ dir => 1 })->each( sub ( $item, $index ) {
    my $should = {
        $permissions->{'__default'}->%*,
        $permissions->{ ( -d $item ) ? '__directory' : '__file' }->%*,
        (
            map { $permissions->{$_}->%* }
            grep { defined }
            map {
                ( my $re = '^' . quotemeta($_) . '$' ) =~ s/\\\*/.*/;
                ( $item->to_rel =~ /$re/ ) ? $_ : undef;
            }
            grep { not /^__/ and /\*/ }
            keys %$permissions
        ),
        %{ $permissions->{ $item->to_rel } // {} },
    };

    unless ( $should->{ignore} ) {
        my $is = {
            prm => sprintf( '%04o', $item->stat->mode & 07777 ),
            usr  => getpwuid( $item->stat->uid ),
            grp  => getpwuid( $item->stat->gid ),
        };

        if (
            $is->{prm} ne $should->{prm} or
            $is->{usr} ne $should->{usr} or
            $is->{grp} ne $should->{grp}
        ) {
            say $item;
            printf "    IS:           %-4s    %-10s %-10s\n", $is->{prm}, $is->{usr}, $is->{grp};
            printf "    SHOULD BE:    %-4s    %-10s %-10s\n", $should->{prm}, $should->{usr}, $should->{grp};
        }
    }
} );

chdir $original_cwd if ( $original_cwd ne $root_dir );

=head1 NAME

permissions.pl - Verify file/directory ownership and permissions

=head1 SYNOPSIS

    permissions.pl OPTIONS
        -u, --cli_user  CLI_USER
        -g, --cli_group CLI_GROUP  # optional; default to CLI_USER
        -r, --ops_user  OPS_USER
        -p, --ops_group OPS_GROUP  # optional; default to OPS_USER
        -h, --help
        -m, --man

=head1 DESCRIPTION

This program will verify file/directory ownership and permissions.

=head2 -u, --cli_user

The "CLI" or checkout user name.

=head2 -g, --cli_group

The "CLI" or checkout group name. Optional; default to the C<cli_user> value.

=head2 -r, --ops_user

The ops user name.

=head2 -p, --ops_group

The ops group name. Optional; default to the C<ops_user> value.
