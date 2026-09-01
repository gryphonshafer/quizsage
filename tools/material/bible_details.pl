#!/usr/bin/env perl
use exact -cli, -conf;
use Omniframe;
use Mojo::UserAgent;
use Term::ANSIColor qw( colored color );
use Text::Unidecode 'unidecode';

my $opt = options( qw{ save|s report|r nocolor|n } );
my $dq  = Omniframe->with_roles('+Database')->new->dq('material');
my $ua  = Mojo::UserAgent->new( max_redirects => 3 );

$dq->get( 'bible', undef, undef, { order_by => 'acronym' } )->run->each( sub ($row) {
    $row->data->{label} //= $row->data->{acronym};

    if ( $row->data->{label} and $row->data->{label} =~ /^BSB\d*$/ ) {
        if ( $row->data->{label} eq 'BSB2022' ) {
            report( $row->data ) if ( $opt->{report} );
            $row->save( 'bible_id', {
                name    => 'Berean Standard Bible',
                year    => 2022,
                acronym => 'BSB22',
            } ) if ( $opt->{save} );
        }
        else {
            my $info = $ua->get('https://biblehub.com/bsb/1_john/1.htm')->result->dom->at('div#botbox');

            my $update = {};
            ( $update->{name} = $info->at('a')->text ) =~ s/\s*\([^\)]*\)\s*//;

            ( $update->{year} ) = ( reverse $info->all_text ) =~ /(\b\d{4}\b)/;
            $update->{year} = reverse $update->{year} if ( $update->{year} );

            report( $row->data, $update ) if ( $opt->{report} );
            $row->save( 'bible_id', $update ) if ( $opt->{save} );
        }
    }
    elsif ( $row->data->{label} and $row->data->{label} =~ /^NIV(\d+)$/ ) {
        my $year = $1;
        report( $row->data ) if ( $opt->{report} );
        $row->save( 'bible_id', {
            name    => 'New International Version',
            year    => $year,
            acronym => 'NIV' . substr( $year, 2 ),
        } ) if ( $opt->{save} );
    }
    elsif ( $row->data->{label} and $row->data->{label} =~ /^ESV(\d+)$/ ) {
        my $year = $1;
        report( $row->data ) if ( $opt->{report} );
        $row->save( 'bible_id', {
            name    => 'English Standard Version',
            year    => $year,
            acronym => 'ESV' . substr( $year, 2 ),
        } ) if ( $opt->{save} );
    }
    else {
        my $info = $ua->get(
            'https://www.biblegateway.com/passage',
            form => {
                search  => '1 John 1:1',
                version => $row->data->{label},
            },
        )->result->dom->at('div.publisher-info-bottom');

        my $update = {};

        $update->{name} = $info->at('strong a')->text;
        $update->{name} =~ s/\s\d{4}\b//;
        $update->{name} =~ s/,//;
        $update->{name} =~ s/[\(\)]//g;

        $update->{name} = qq{Hawai\x{2019}i Pidgin}
            if ( substr( $update->{name}, 0, 5 ) eq 'Hawai' );

        ( $update->{year} ) = ( reverse $info->find('p')->map('text')->join(' ') ) =~ /(\b\d{4}\b)/;
        $update->{year} = reverse $update->{year} if ( $update->{year} );

        $update->{acronym} = 'NASB5' if ( $row->data->{acronym} eq 'NASB1995' );
        $update->{year} = 1901 if ( not $update->{year} and $row->data->{acronym} eq 'AKJV' );
        $update->{year} = 1769 if ( not $update->{year} and $row->data->{acronym} eq 'KJV' );

        report( $row->data, $update ) if ( $opt->{report} );
        $row->save( 'bible_id', $update ) if ( $opt->{save} );
    }
} );

sub report ( $current, $update = undef ) {
    my $line = sprintf(
        '%-5s %-10s %-42s %s',
        $current->{acronym},
        '(' . ( $current->{label} // '' ) . ')',
        "\x{201c}" . ( $current->{name} // '' ) . "\x{201d}",
        ( $current->{year} // '' ),
    );

    if (
        $update and (
            $current->{name} and $current->{name} ne $update->{name} or
            $current->{year} and $current->{year} ne $update->{year}
        )
    ) {
        $line .= " \x{2192} " . $update->{year} . " \x{201c}" . $update->{name} . "\x{201d}";
        $line = colored( $line, 'bright_red' ) unless $opt->{nocolor};
    }

    $line = unidecode $line if $opt->{nocolor};
    say $line;
}

=head1 NAME

bible_details.pl - Add/update Bible details in material database from sources

=head1 SYNOPSIS

    bible_details.pl OPTIONS
        -s, --save    # save add/update to database
        -r, --report  # report on bibles details (and red-mark any delta)
        -n, --nocolor
        -h, --help
        -m, --man

=head1 DESCRIPTION

This program will add or update Bible details in material database from sources.
