#!/usr/bin/env perl
use exact -cli, -conf;
use Omniframe;
use Mojo::UserAgent;

my $dq = Omniframe->with_roles('+Database')->new->dq('material');
my $ua = Mojo::UserAgent->new( max_redirects => 3 );

$dq->get('bible')->run->each( sub ($row) {
    my $info = $ua->get(
        'https://www.biblegateway.com/passage',
        form => {
            search  => '1 John 1:1',
            version => $row->data->{label},
        },
    )->result->dom->at('div.publisher-info-bottom');

    if ($info) {
        my $update = {};

        $update->{name} = $info->at('strong a')->text;
        $update->{name} =~ s/\s\d{4}\b//;
        $update->{name} =~ s/,//;
        $update->{name} =~ s/[\(\)]//g;

        ( $update->{year} ) = ( reverse $info->find('p')->map('text')->join(' ') ) =~ /(\b\d{4}\b)/;
        $update->{year} = reverse $update->{year} if ( $update->{year} );

        $update->{acronym} = 'NASB5' if ( $row->data->{acronym} eq 'NASB1995' );
        $update->{year} = 1901 if ( not $update->{year} and $row->data->{acronym} eq 'AKJV' );
        $update->{year} = 1769 if ( not $update->{year} and $row->data->{acronym} eq 'KJV' );

        $row->save( 'bible_id', $update );
    }
    elsif ( $row->data->{label} eq 'BSB' ) {
        $row->save( 'bible_id', { name => 'Berean Standard Bible', year => 2023 } );
    }
} );

=head1 NAME

bible_details.pl - Add Bible details to material database from Bible Gateway

=head1 SYNOPSIS

    bible_details.pl OPTIONS
        -h, --help
        -m, --man

=head1 DESCRIPTION

This program will add Bible details to material database from Bible Gateway.
