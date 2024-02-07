package QuizSage::Role::Data;

use exact -role;
use Mojo::JSON 'decode_json';
use Mojo::File 'path';
use YAML::XS qw( LoadFile Load Dump );

with 'Omniframe::Role::Conf';

sub deepcopy ( $self, @items ) {
    return unless (@items);
    my @results = map { Load( Dump($_) ) } @items;
    return ( @results == 1 ) ? $results[0] : ( wantarray ) ? @results : \@results;
}

sub dataload ( $self, $file ) {
    my $path = path( $self->conf->get( qw( config_app root_dir ) ) . '/' . $file );
    return
        ( $file =~ /\.yaml$/i ) ? LoadFile($path)             :
        ( $file =~ /\.json$/i ) ? decode_json( $path->slurp ) : $path->slurp;
}

1;

=head1 NAME

QuizSage::Role::Data

=head1 SYNOPSIS

    package Package;

    use exact -class;

    with 'QuizSage::Role::Data';

=head1 DESCRIPTION

This role provides some Data methods.

=head1 METHODS

=head2 deepcopy

=head2 dataload

=head1 WITH ROLE

L<Omniframe::Role::Conf>.
